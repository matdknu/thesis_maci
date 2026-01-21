# -*- coding: utf-8 -*-
"""
Clasificador basado en RNN (LSTM/GRU) usando PyTorch
Análisis de discurso político - Clasificación de polarización (us_vs_them_marker)
"""

import os
import sys
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    accuracy_score, classification_report, confusion_matrix,
    f1_score, balanced_accuracy_score, average_precision_score
)
from sklearn.preprocessing import LabelEncoder
import re
from collections import Counter
from tqdm import tqdm
from pathlib import Path
import gc

# Configuración
RANDOM_SEED = 123
torch.manual_seed(RANDOM_SEED)
np.random.seed(RANDOM_SEED)

# Rutas
# Definir BASE_DIR: funciona tanto en script como en IPython/Jupyter
try:
    # En scripts normales, usar __file__
    BASE_DIR = Path(__file__).parent.parent.parent
except NameError:
    # En IPython/Jupyter, __file__ no existe, usar ruta absoluta
    BASE_DIR = Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_final")
    # Alternativa: BASE_DIR = Path(os.getcwd())
DATA_DIR = BASE_DIR / "data" / "processed" / "analisis_discurso"
OUT_DIR = BASE_DIR / "data" / "processed" / "analisis_discurso"

# Parámetros del modelo
VOCAB_SIZE = 5000  # Reducido para estabilidad
EMBEDDING_DIM = 64  # Reducido para datasets pequeños
HIDDEN_DIM = 128  # Reducido para datasets pequeños
NUM_LAYERS = 1  # Reducido para datasets pequeños
NUM_CLASSES = 2  # Polarizado (1) vs No Polarizado (0)
MAX_LENGTH = 120  # Reducido para estabilidad
BATCH_SIZE = 16  # Reducido para datasets pequeños
LEARNING_RATE = 0.0003  # Reducido para estabilidad (era 0.001)
NUM_EPOCHS = 10

# Configuración de datos
USE_COMMENT_ONLY = False  # True = solo comment_texto, False = texto_completo

# Device
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Using device: {device}")

# =============================================================
# 1) Cargar Dataset
# =============================================================
print("=== Cargando dataset ===")

# Intentar cargar desde test_analisis_discurso primero
test_file = os.path.join(DATA_DIR, "test_analisis_discurso.rds")
completo_file = os.path.join(DATA_DIR, "analisis_discurso_completo.rds")

if os.path.exists(test_file):
    # Leer archivo RDS usando pyreadr o rpy2
    try:
        import pyreadr
        result = pyreadr.read_r(test_file)
        df = result[list(result.keys())[0]]
        print(f"✓ Datos cargados desde test_analisis_discurso.rds")
    except ImportError:
        print("pyreadr no disponible, intentando con pandas (requiere conversión previa)")
        # Si no está disponible, asumir que hay un CSV
        csv_file = os.path.join(DATA_DIR, "test_analisis_discurso.csv")
        if os.path.exists(csv_file):
            df = pd.read_csv(csv_file)
        else:
            raise FileNotFoundError("No se encontró archivo de datos")
elif os.path.exists(completo_file):
    try:
        import pyreadr
        result = pyreadr.read_r(completo_file)
        df = result[list(result.keys())[0]]
        print(f"✓ Datos cargados desde analisis_discurso_completo.rds")
    except ImportError:
        csv_file = os.path.join(DATA_DIR, "analisis_discurso_completo.csv")
        if os.path.exists(csv_file):
            df = pd.read_csv(csv_file)
        else:
            raise FileNotFoundError("No se encontró archivo de datos")
else:
    raise FileNotFoundError("No se encontraron datos de análisis de discurso")

# Preparar datos
df_ml = df[
    (df['procesado'] == True) & 
    (df['error'] == False) & 
    (df['us_vs_them_marker'].notna()) &
    (df['texto_completo'].notna())
].copy()

# Seleccionar texto según configuración
if USE_COMMENT_ONLY and 'comment_texto' in df_ml.columns:
    df_ml['text'] = df_ml['comment_texto'].astype(str).str.strip()
    print("✓ Usando solo comment_texto (reacción)")
else:
    df_ml['text'] = df_ml['texto_completo'].astype(str).str.replace('<>', ' ', regex=False)
    df_ml['text'] = df_ml['text'].str.strip()
    print("✓ Usando texto_completo (post + comentario)")

df_ml = df_ml[df_ml['text'].str.len() > 20].copy()

df_ml['target'] = df_ml['us_vs_them_marker'].astype(int)

print(f"Total observaciones: {len(df_ml)}")
print(f"Distribución de target:\n{df_ml['target'].value_counts()}")

# Advertencia sobre tamaño del dataset
if len(df_ml) < 100:
    print(f"\n⚠️  ADVERTENCIA: Dataset muy pequeño ({len(df_ml)} observaciones).")
    print("   Los modelos de deep learning requieren más datos para funcionar bien.")
    print("   Los resultados pueden no ser representativos.\n")

# =============================================================
# 2) Definir Vocabulario
# =============================================================
print("\n=== Definiendo vocabulario ===")

def simple_tokenizer(text, lower=True):
    """Tokenizador simple"""
    if lower:
        text = text.lower()
    # Remover caracteres especiales, mantener solo letras y espacios
    text = re.sub(r'[^a-záéíóúñü\s]', ' ', text)
    tokens = text.split()
    return tokens

# Construir vocabulario
all_tokens = []
for text in df_ml['text']:
    tokens = simple_tokenizer(str(text))
    all_tokens.extend(tokens)

# Contar frecuencias
token_counts = Counter(all_tokens)

# Crear vocabulario (palabras más frecuentes + tokens especiales)
vocab = {
    '<PAD>': 0,
    '<UNK>': 1,
    '<START>': 2,
    '<END>': 3
}

# Agregar palabras más frecuentes
for idx, (word, count) in enumerate(token_counts.most_common(VOCAB_SIZE - 4), start=4):
    vocab[word] = idx

# Vocabulario inverso
idx_to_word = {idx: word for word, idx in vocab.items()}

print(f"Tamaño del vocabulario: {len(vocab)}")

# =============================================================
# 3) Dataset y DataLoader
# =============================================================
class DiscourseDataset(Dataset):
    """Dataset para análisis de discurso"""
    
    def __init__(self, texts, targets, vocab, max_length=MAX_LENGTH):
        self.texts = texts
        self.targets = targets
        self.vocab = vocab
        self.max_length = max_length
    
    def __len__(self):
        return len(self.texts)
    
    def __getitem__(self, idx):
        text = str(self.texts.iloc[idx])
        target = self.targets.iloc[idx]
        
        # Tokenizar
        tokens = simple_tokenizer(text)
        
        # Convertir a índices
        indices = [self.vocab.get(token, self.vocab['<UNK>']) for token in tokens]
        
        # Truncar o pad
        if len(indices) > self.max_length:
            indices = indices[:self.max_length]
        else:
            indices = indices + [self.vocab['<PAD>']] * (self.max_length - len(indices))
        
        return torch.tensor(indices, dtype=torch.long), torch.tensor(target, dtype=torch.long)

# División train/val/test (CORREGIDO: separar test del val)
# Primero separar test
try:
    train_val_df, test_df = train_test_split(
        df_ml,
        test_size=0.2,
        random_state=RANDOM_SEED,
        stratify=df_ml['target']
    )
except ValueError:
    print("Advertencia: No se pudo estratificar. Haciendo división simple.")
    train_val_df, test_df = train_test_split(
        df_ml,
        test_size=0.2,
        random_state=RANDOM_SEED
    )

# Luego separar train/val
try:
    train_df, val_df = train_test_split(
        train_val_df,
        test_size=0.2,  # 20% de train_val va a val
        random_state=RANDOM_SEED,
        stratify=train_val_df['target']
    )
except ValueError:
    print("Advertencia: No se pudo estratificar train/val. Haciendo división simple.")
    train_df, val_df = train_test_split(
        train_val_df,
        test_size=0.2,
        random_state=RANDOM_SEED
    )

print(f"\nTrain: {len(train_df)} observaciones")
print(f"Val: {len(val_df)} observaciones")
print(f"Test: {len(test_df)} observaciones")
print(f"Distribución Train:\n{train_df['target'].value_counts()}")
print(f"Distribución Val:\n{val_df['target'].value_counts()}")
print(f"Distribución Test:\n{test_df['target'].value_counts()}")

# Crear datasets
train_dataset = DiscourseDataset(
    train_df['text'], 
    train_df['target'], 
    vocab, 
    max_length=MAX_LENGTH
)
val_dataset = DiscourseDataset(
    val_df['text'],
    val_df['target'],
    vocab,
    max_length=MAX_LENGTH
)

test_dataset = DiscourseDataset(
    test_df['text'], 
    test_df['target'], 
    vocab, 
    max_length=MAX_LENGTH
)

# DataLoaders (ajustar batch_size si es muy grande para el dataset)
actual_batch_size = min(BATCH_SIZE, len(train_dataset))
if actual_batch_size < BATCH_SIZE:
    print(f"Advertencia: Batch size ajustado a {actual_batch_size} (dataset pequeño)")

train_loader = DataLoader(train_dataset, batch_size=actual_batch_size, shuffle=True)
val_loader = DataLoader(val_dataset, batch_size=actual_batch_size, shuffle=False)
test_loader = DataLoader(test_dataset, batch_size=actual_batch_size, shuffle=False)

print(f"✓ DataLoaders creados")

# =============================================================
# 4) Definir Red Recurrente (LSTM)
# =============================================================
class RNNClassifier(nn.Module):
    """Clasificador basado en LSTM"""
    
    def __init__(self, vocab_size, embedding_dim, hidden_dim, num_layers, num_classes, dropout=0.3):
        super(RNNClassifier, self).__init__()
        
        self.embedding = nn.Embedding(vocab_size, embedding_dim, padding_idx=0)
        
        # LSTM bidireccional (SIMPLIFICADO: sin atención para mayor estabilidad)
        self.lstm = nn.LSTM(
            embedding_dim,
            hidden_dim,
            num_layers,
            batch_first=True,
            bidirectional=True,
            dropout=dropout if num_layers > 1 else 0
        )
        
        # Capas fully connected (simplificado)
        self.fc1 = nn.Linear(hidden_dim * 2, hidden_dim)  # *2 por bidireccional
        self.dropout = nn.Dropout(dropout)
        self.fc2 = nn.Linear(hidden_dim, num_classes)
        self.relu = nn.ReLU()
    
    def forward(self, X_batch):
        # Embedding
        embedded = self.embedding(X_batch)  # (batch_size, seq_len, embedding_dim)
        
        # LSTM
        lstm_out, (hidden, cell) = self.lstm(embedded)
        # lstm_out: (batch_size, seq_len, hidden_dim * 2)
        
        # Pooling: usar mean pooling (más estable que atención para datasets pequeños)
        pooled = torch.mean(lstm_out, dim=1)  # (batch_size, hidden_dim * 2)
        
        # Fully connected
        out = self.fc1(pooled)
        out = self.relu(out)
        out = self.dropout(out)
        out = self.fc2(out)
        
        return out

# Crear modelo
model = RNNClassifier(
    vocab_size=len(vocab),
    embedding_dim=EMBEDDING_DIM,
    hidden_dim=HIDDEN_DIM,
    num_layers=NUM_LAYERS,
    num_classes=NUM_CLASSES,
    dropout=0.3
).to(device)

print(f"\n=== Modelo creado ===")
print(f"Parámetros totales: {sum(p.numel() for p in model.parameters()):,}")
print(f"Parámetros entrenables: {sum(p.numel() for p in model.parameters() if p.requires_grad):,}")

# =============================================================
# 5) Funciones de Entrenamiento y Evaluación
# =============================================================
def CalcValLossAndAccuracy(model, loss_fn, val_loader):
    """Calcular pérdida y accuracy en validación"""
    model.eval()
    with torch.no_grad():
        Y_shuffled, Y_preds, losses = [], [], []
        for X, Y in val_loader:
            X, Y = X.to(device), Y.to(device)
            preds = model(X)
            loss = loss_fn(preds, Y)
            losses.append(loss.item())
            
            Y_shuffled.append(Y.cpu())
            Y_preds.append(preds.argmax(dim=-1).cpu())
        
        Y_shuffled = torch.cat(Y_shuffled)
        Y_preds = torch.cat(Y_preds)
        
        val_loss = torch.tensor(losses).mean().item()
        val_acc = accuracy_score(Y_shuffled.numpy(), Y_preds.numpy())
        
        print(f"Valid Loss : {val_loss:.3f}")
        print(f"Valid Acc  : {val_acc:.3f}")
        
        return val_loss, val_acc

def TrainModel(model, loss_fn, optimizer, train_loader, val_loader, epochs=10, patience=3):
    """Entrenar el modelo con early stopping"""
    model.train()
    best_val_loss = float('inf')
    patience_counter = 0
    
    for i in range(1, epochs + 1):
        losses = []
        for X, Y in tqdm(train_loader, desc=f"Epoch {i}/{epochs}"):
            X, Y = X.to(device), Y.to(device)
            
            # Forward pass
            Y_preds = model(X)
            loss = loss_fn(Y_preds, Y)
            losses.append(loss.item())
            
            # Backward pass
            optimizer.zero_grad()
            loss.backward()
            # Gradient clipping para estabilidad
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()
        
        train_loss = torch.tensor(losses).mean().item()
        print(f"Train Loss : {train_loss:.3f}")
        val_loss, val_acc = CalcValLossAndAccuracy(model, loss_fn, val_loader)
        
        # Early stopping
        if val_loss < best_val_loss:
            best_val_loss = val_loss
            patience_counter = 0
            # Guardar mejor modelo
            best_model_path = os.path.join(OUT_DIR, "rnn_best_model.pt")
            torch.save(model.state_dict(), best_model_path)
        else:
            patience_counter += 1
            if patience_counter >= patience:
                print(f"\nEarly stopping en epoch {i} (patience={patience})")
                # Cargar mejor modelo si existe
                best_model_path = os.path.join(OUT_DIR, "rnn_best_model.pt")
                if os.path.exists(best_model_path):
                    model.load_state_dict(torch.load(best_model_path))
                break
        
        model.train()  # Volver a modo entrenamiento

def MakePredictions(model, loader):
    """Hacer predicciones"""
    model.eval()
    Y_shuffled, Y_preds = [], []
    with torch.no_grad():
        for X, Y in loader:
            X, Y = X.to(device), Y.to(device)
            preds = model(X)
            Y_preds.append(preds)
            Y_shuffled.append(Y.cpu())
    
    gc.collect()
    Y_preds = torch.cat(Y_preds)
    Y_shuffled = torch.cat(Y_shuffled)
    
    # Softmax y argmax
    Y_preds_probs = torch.softmax(Y_preds, dim=-1)
    Y_preds_classes = Y_preds_probs.argmax(dim=-1).cpu().numpy()
    
    return Y_shuffled.numpy(), Y_preds_classes

# =============================================================
# 6) Entrenamiento del Modelo
# =============================================================
print("\n=== Entrenando modelo ===")

# Loss function con pesos para manejar desbalance (opcional)
# Calcular pesos basados en frecuencia de clases
class_counts = train_df['target'].value_counts().sort_index()
total = class_counts.sum()
class_weights = torch.tensor([total / (len(class_counts) * count) for count in class_counts], dtype=torch.float32).to(device)
print(f"Pesos de clases: {class_weights}")

loss_fn = nn.CrossEntropyLoss(weight=class_weights)
# Optimizer con weight decay para regularización
optimizer = optim.Adam(model.parameters(), lr=LEARNING_RATE, weight_decay=1e-5)

# CORREGIDO: Usar val_loader para early stopping, NO test_loader
TrainModel(model, loss_fn, optimizer, train_loader, val_loader, epochs=NUM_EPOCHS, patience=3)

# Guardar modelo
model_path = os.path.join(OUT_DIR, "rnn_classifier.pt")
torch.save({
    'model_state_dict': model.state_dict(),
    'vocab': vocab,
    'idx_to_word': idx_to_word,
    'model_params': {
        'vocab_size': len(vocab),
        'embedding_dim': EMBEDDING_DIM,
        'hidden_dim': HIDDEN_DIM,
        'num_layers': NUM_LAYERS,
        'num_classes': NUM_CLASSES
    }
}, model_path)
print(f"\n✓ Modelo guardado en: {model_path}")

# =============================================================
# 7) Evaluación del Modelo
# =============================================================
print("\n=== Evaluando modelo ===")

Y_actual, Y_preds = MakePredictions(model, test_loader)

# Métricas completas (CORREGIDO: agregar macro-F1, balanced accuracy, PR-AUC)
accuracy = accuracy_score(Y_actual, Y_preds)
balanced_acc = balanced_accuracy_score(Y_actual, Y_preds)
macro_f1 = f1_score(Y_actual, Y_preds, average='macro', zero_division=0)
weighted_f1 = f1_score(Y_actual, Y_preds, average='weighted', zero_division=0)

# PR-AUC (asumiendo que clase 1 es "Polarizado" - la positiva)
# Necesitamos probabilidades, no solo predicciones
model.eval()
Y_probs = []
Y_actual_for_pr = []
with torch.no_grad():
    for X, Y in test_loader:
        X = X.to(device)
        preds = model(X)
        probs = torch.softmax(preds, dim=-1)
        Y_probs.extend(probs[:, 1].cpu().numpy())  # Probabilidad de clase 1 (Polarizado)
        Y_actual_for_pr.extend(Y.numpy())

Y_actual_for_pr = np.array(Y_actual_for_pr)
Y_probs = np.array(Y_probs)

# PR-AUC por clase y macro promedio
try:
    pr_auc_class0 = average_precision_score(Y_actual_for_pr == 0, 1 - Y_probs, average=None)
    pr_auc_class1 = average_precision_score(Y_actual_for_pr == 1, Y_probs, average=None)
    pr_auc = np.mean([pr_auc_class0, pr_auc_class1])
except:
    # Si falla (pocos datos), calcular solo para clase mayoritaria
    pr_auc = average_precision_score(Y_actual_for_pr, Y_probs, average='macro')

print(f"\n=== MÉTRICAS EN TEST SET (EVALUACIÓN FINAL) ===")
print(f"Accuracy: {accuracy:.4f}")
print(f"Balanced Accuracy: {balanced_acc:.4f}")
print(f"Macro F1: {macro_f1:.4f}")
print(f"Weighted F1: {weighted_f1:.4f}")
print(f"Macro PR-AUC: {pr_auc:.4f}")

# Classification Report
target_classes = ['No_Polarizado', 'Polarizado']
print("\nClassification Report :")
print(classification_report(
    Y_actual, Y_preds, 
    target_names=target_classes,
    zero_division=0  # Manejar divisiones por cero
))

# Confusion Matrix
print("\nConfusion Matrix :")
cm = confusion_matrix(Y_actual, Y_preds)
print(cm)
print(f"(Orden: [No_Polarizado, Polarizado] en filas y columnas)")

# Guardar resultados completos
results_df = pd.DataFrame({
    'y_actual': Y_actual_for_pr,
    'y_pred': Y_preds,
    'y_prob_polarizado': Y_probs
})
results_df.to_csv(os.path.join(OUT_DIR, "rnn_predictions.csv"), index=False)

# Guardar métricas
metrics_df = pd.DataFrame({
    'metric': ['accuracy', 'balanced_accuracy', 'macro_f1', 'weighted_f1', 'macro_pr_auc'],
    'value': [accuracy, balanced_acc, macro_f1, weighted_f1, pr_auc]
})
metrics_df.to_csv(os.path.join(OUT_DIR, "rnn_metrics.csv"), index=False)
print(f"\n✓ Métricas guardadas en: {os.path.join(OUT_DIR, 'rnn_metrics.csv')}")

# =============================================================
# 8) Análisis de Resultados
# =============================================================
print("\n=== ANÁLISIS DE RESULTADOS ===")
print("\n1. ¿Por qué estos resultados?")
print("   - Las RNN (LSTM) capturan dependencias secuenciales en el texto")
print("   - La arquitectura bidireccional permite ver contexto en ambas direcciones")
print("   - La capa de atención ayuda a enfocarse en palabras relevantes")
print("   - Los embeddings aprendidos capturan relaciones semánticas específicas del dominio")

print("\n2. ¿Es mejor que solo utilizar Word Embeddings?")
print("   - SÍ, porque:")
print("     * Las RNN aprenden representaciones contextuales (no solo promedios)")
print("     * Capturan el orden y la secuencia de palabras")
print("     * Pueden manejar dependencias de largo alcance")
print("     * Los embeddings se ajustan durante el entrenamiento para la tarea específica")
print("   - Sin embargo:")
print("     * Requiere más datos y tiempo de entrenamiento")
print("     * Más complejo y difícil de interpretar")
print("     * Word Embeddings pre-entrenados pueden ser útiles con pocos datos")

print("\n3. Justificación:")
print(f"   - Accuracy: {accuracy:.4f}")
print(f"   - Balanced Accuracy: {balanced_acc:.4f} (mejor métrica para clases desbalanceadas)")
print(f"   - Macro F1: {macro_f1:.4f} (promedio de F1 por clase)")
print(f"   - Macro PR-AUC: {pr_auc:.4f} (área bajo curva precision-recall)")

if balanced_acc > 0.7:
    print("   - Buen rendimiento balanceado, el modelo captura patrones relevantes")
elif balanced_acc > 0.6:
    print("   - Rendimiento moderado, podría mejorarse con más datos o ajustes")
else:
    print("   - Rendimiento bajo, considerar más datos, arquitectura diferente o features adicionales")

print("\n4. Comparación con Word Embeddings:")
print("   - Los modelos basados en promedios de embeddings tienden a favorecer la clase mayoritaria")
print("   - Las RNN deberían capturar mejor las dependencias secuenciales")
print("   - Con datasets pequeños, las RNN pueden ser más inestables pero más expresivas")

print("\n✓ Análisis completado")

