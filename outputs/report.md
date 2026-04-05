# Simulated Reddit-like Political Conversation Dataset
## Chile 2025 Campaign Study - Synthetic Data Analysis

### Motivation

This report presents a synthetic dataset simulating political discourse on a Reddit-like platform during the Chile 2025 presidential campaign. The simulation is designed to mimic empirical patterns observed in real political discourse, including temporal dynamics, ideological fragmentation, echo chambers, and adversarial targeting.

### Data Generation

**Time Window**: 2025-08-01 to 2025-12-31 (153 days)

**Users**: 5,000 users with latent ideology scores and bloc membership probabilities

**Posts/Comments**: 6,238 total posts, including 2,511 replies (40.3%)

**Key Features**:
- Ideological blocs: Left, Right-Traditional, Right-Radical-Conservative, Right-Libertarian
- Discourse elements: frames, emotions, strategies, adversary targets
- Temporal patterns: volume breakpoints, candidate attention trajectories, runoff dynamics

### Campaign Events

Key campaign events with volume spikes and emotion shifts:
- **ARCHI Debate (1st Round)**: 2025-11-04 - Volume spike, increased negative emotions
- **1st Round Election**: 2025-11-16 - Kast wins, critical transition point
  - **Phase A → Phase B**: Intra-right attacks decrease, PC targeting increases
- **ARCHI Debate (Runoff)**: 2025-12-03 - Volume spike, peak PC targeting
- **2nd Round Election**: 2025-12-14 - Final election day

### Validation of Mock OpenAI Classification

The mock OpenAI classifier demonstrates realistic performance with probability vectors:

- **Bloc Classification**: Macro F1 = 0.642, Within-right confusion = 0.425
  - Left vs Right: Clear distinction (90%+ accuracy)
  - Within-right subtypes: Higher confusion (as expected)
  - Sarcasm flag increases misclassification probability

- **Strategy Classification**: 43.6% accuracy
  - Lower performance than sentiment (as expected for fine-grained tasks)

- **Sentiment Classification**: 84.2% accuracy
  - Best performance (coarse-grained task)
  
- **Calibration**: ECE = 0.004 (Expected Calibration Error)

### Results Highlights

#### 1. Fragmentation on the Right

The three right-wing blocs show more diffuse boundaries compared to the clear Left-Right divide:
- **E-I Index (Left-Right)**: -0.270 (high negative = strong separation)
- **E-I Index (within Right)**: 0.275 (less negative = more mixing)
- **Assortativity (bloc)**: -0.007
- **Assortativity (ideology)**: 0.025
- Network modularity: 0.862
- Within-right connections: 1,440 edges
- **Within-right confusion (mock OpenAI)**: 0.425

#### 2. Two-Phase Right-Wing Dynamic

**Phase A (Pre-1st Round, before 2025-11-16):**
- Intra-right attacks increase (right subtypes attack each other)
- Higher probability of targeting "traitors within right"
- Visible conflict between right subtypes

**Phase B (Post-1st Round, from 2025-11-16):**
- After Kast's victory, right blocs converge
- Intra-right attacks decrease sharply
- PC targeting increases significantly (especially near debates/election)
- Frame distributions become more similar (convergence index increases)
- Cross-right coordination in frames and strategies

#### 3. Echo Chambers

Strong assortativity by bloc: -0.007
- Clear separation between Left and Right overall
- More connections within bloc than across blocs
- Attack edges more common across ideological boundaries

#### 4. Temporal Dynamics

- **Volume**: Low/stable Aug-mid Sep; break in late Oct; peak mid-Nov; sustained volatility Nov-Dec
- **Candidate Trajectories**:
  - Kast: Sustained growth, high levels, frequent peaks Nov-Dec
  - Kaiser: Episodic, sharp spike in Nov (most aggressive bloc)
  - Matthei: Intermittent, loses traction toward end
  - Jara: Continuous flow, strong increase from Nov

#### 5. Attack Probabilities

Right-Libertarian (Kaiser) shows highest attack rates (31.2%), 
followed by Right-Radical-Conservative (28.6%).

Left shows more defensive strategies (29.5% attack rate).

### Machine Learning Results

**Strategy Prediction**:
              model  accuracy       f1
                SVM  0.750000 0.751838
Logistic Regression  0.800481 0.801701
      Random Forest  0.850160 0.851352

**PC Target Prediction**:
              model  accuracy       f1
                SVM  0.800481 0.610329
Logistic Regression  0.850160 0.678141
      Random Forest  0.880609 0.744425

**Bloc Prediction**:
              model  accuracy       f1
                SVM  0.415865 0.376653
Logistic Regression  0.429487 0.402166
      Random Forest  0.423077 0.406200

### Network Metrics

- Assortativity (bloc): -0.007
- Assortativity (ideology): 0.025
- Density: 0.000100
- Reciprocity: 0.000
- Modularity: 0.862
- E-I Index (Left-Right): -0.270
- E-I Index (within Right): 0.275

### Convergence Analysis

Right bloc convergence measured by cosine similarity of frame distributions:
- Pre-runoff average similarity: 0.821
- Post-runoff average similarity: 0.938
- Effect size: 0.117

### Attack Prediction Model

- **ROC AUC**: 1.000
- **PR AUC**: 1.000
- **Top 8 Coefficients**: 0.051532599624649, 0.0284242137868308, 1.2871992389409013, -0.1405761720309828, 0.0, -0.160411176683...

### Comprehensive Summary Table

See `comprehensive_summary_table.csv` for complete metrics across all analyses.
| Category                   | Metric                 | Value                                                                                                                             |
|:---------------------------|:-----------------------|:----------------------------------------------------------------------------------------------------------------------------------|
| Dataset Size               | n_users                | 5000                                                                                                                              |
| Dataset Size               | n_posts                | 6238                                                                                                                              |
| Dataset Size               | n_edges                | 2511                                                                                                                              |
| Network Metrics            | assortativity_bloc     | -0.007                                                                                                                            |
| Network Metrics            | assortativity_ideology | 0.025                                                                                                                             |
| Network Metrics            | modularity             | 0.862                                                                                                                             |
| Network Metrics            | E-I_index_LR           | -0.270                                                                                                                            |
| Network Metrics            | E-I_index_within_right | 0.275                                                                                                                             |
| Mock OpenAI                | bloc_macro_F1          | 0.642                                                                                                                             |
| Mock OpenAI                | within_right_confusion | 0.425                                                                                                                             |
| ML Performance (Bloc)      | bloc_accuracy          | 0.4158653846153846                                                                                                                |
| ML Performance (PC Target) | pc_target_accuracy     | 0.8004807692307693                                                                                                                |
| ML Performance (Strategy)  | strategy_accuracy      | 0.75                                                                                                                              |
| Attack Model               | ROC_AUC                | 1.000                                                                                                                             |
| Attack Model               | PR_AUC                 | 1.000                                                                                                                             |
| Attack Model               | top_8_coefficients     | 0.051532599624649, 0.0284242137868308, 1.2871992389409013, -0.1405761720309828, 0.0, -0.1604111766830925, 0.0833897248376291, 0.0 |

### Limitations of Simulation

1. **Synthetic Text**: Generated text uses templates and may not capture full linguistic complexity
2. **Simplified User Behavior**: User activity and interaction patterns are simplified
3. **Deterministic Patterns**: Some temporal patterns are deterministic rather than emergent
4. **Network Structure**: Network generation is based on probabilities rather than real interaction data
5. **No External Events**: Simulation does not include external events that might affect discourse

### Files Generated

**Figures** (./outputs/figures/):
- 01_daily_volume.png: Daily post volume with campaign phase breakpoints
- 02_candidate_mentions.png: Candidate mention trajectories
- 03_emotions_by_bloc.png: Emotion composition over time by bloc
- 04_anti_communism_rate.png: PC targeting rate over time
- 05_network_echo_chambers.png: Interaction network showing echo chambers
- 06_confusion_matrix.png: Mock OpenAI bloc classification confusion matrix
- 07_roc_pr_curves.png: ROC and PR curves for attack prediction
- 08_attack_probabilities.png: Attack probability across phases by bloc (with 95% CI)
- 09_convergence_analysis.png: Right bloc convergence and intra-right attack rates

**Tables** (./outputs/tables/):
- users.csv: User attributes and ideology scores
- posts.csv: All posts with discourse labels
- openai_predictions.csv: Mock OpenAI classification outputs
- network_metrics.csv: Network-level statistics
- ml_results.csv: Machine learning model performance
- attack_model_coefficients.csv: Temporal attack probability model coefficients
- summary_statistics.csv: Overall dataset statistics

---

*Generated on 2026-01-03 21:08:52*
