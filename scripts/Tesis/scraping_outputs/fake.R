library(tidyverse)
library(igraph)
library(ggraph)
library(stringr)
library(scales)

# -----------------------------
# 1) Data
# -----------------------------
library(tidyverse)
library(igraph)
library(ggraph)
library(stringr)
library(scales)

# -----------------------------
# 1) Data (English translation)
# -----------------------------
df <- tribble(
  ~comment_id,     ~parent_id,      ~author,         ~stance,             ~created_utc, ~score_polarizante, ~body,
  "central_post",  NA,              "OP_mod",        "neutral",           1764547200,  0,
  "What do you think about the communist candidate now calling herself a social democrat?",
  
  "c01",           "central_post",  "Rafa_2e21e", "radical_right",     1764549000,  25,
  "Even though Chilean communists have long claimed to support democracy, they still call themselves \"revolutionary Marxists\"—which is contradictory.",
  
  "c02",           "c01",           "LindaBoxi",    "left",              1764549300,  99,
  "Communists are absolute pieces of shit at blending in—never trust them.",
  
  "c03",           "c02",           "Libertari0s", "libertarian_right", 1764549600,  65,
  "Social democrat and communist—same thing? Sounds like pure electoral makeup [Laughing emoji].",
  
  "c04",           "c02",           "User232e1",    "neutral",           1764549900,  20,
  "The Communist Party has competed within democratic institutions for decades. We can criticize them, but saying \"it’s all the same\" erases important nuances.",
  
  "c06",           "c04",           "RedditUser323r3",   "radical_right",     1764550050,  90,
  "Communists live off the \"Che Guevara\" fairy tale and don’t understand democracy. They’re idiots.",
  
  "c07",           "c04",           "ChileanTrump", "left",              1764550120,  75,
  "What you’re doing is pure whitewashing. If it were up to the communists, Chile would be Venezuela.",
  
  "c05",           "central_post",  "Seba_Diaz", "neutral",           1764550200,  10,
  "No insults: what concrete policies actually change with that shift? If there’s no clear platform, it’s just rebranding."
) %>%
  mutate(
    created_dt = as.POSIXct(created_utc, origin = "1970-01-01", tz = "UTC"),
    stance = factor(stance),
    score_polarizante = pmax(score_polarizante, 0)
  )

# -----------------------------
# 2) Graph
# -----------------------------
edges <- df %>%
  filter(!is.na(parent_id) & parent_id != "") %>%
  transmute(from = parent_id, to = comment_id)

nodes <- df %>%
  transmute(
    name = comment_id,
    author,
    stance,
    created_dt,
    score_polarizante,
    body
  )

g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)

# -----------------------------
# 3) Labels + aesthetics
# -----------------------------
wrap_width <- 38

V(g)$label <- paste0(
  V(g)$author, " · ", V(g)$name, "\n",
  str_wrap(V(g)$body, width = wrap_width)
)

V(g)$size_plot <- rescale(pmax(V(g)$score_polarizante, 5), to = c(5, 15))

V(g)$is_discussion <- V(g)$name %in% c("c02", "c03", "c04", "c06", "c07")
V(g)$is_root <- V(g)$name == "central_post"

E(g)$w <- V(g)[ends(g, E(g))[,2]]$score_polarizante
E(g)$w_plot <- rescale(pmax(E(g)$w, 1), to = c(0.4, 2.2))

# -----------------------------
# 4) Plot (ROOT UP + distinct central post)
# -----------------------------
set.seed(123)

pal <- c("#2c7bb6", "#abd9e9", "#ffffbf", "#fdae61", "#d7191c")
lim_max <- max(V(g)$score_polarizante)

p <- ggraph(g, layout = "dendrogram") +
  
  geom_edge_link(
    aes(width = w_plot),
    alpha = 0.30,
    lineend = "round",
    arrow = arrow(length = unit(3, "mm"))
  ) +
  
  geom_node_point(
    data = function(x) dplyr::filter(x, is_discussion),
    aes(size = size_plot),
    shape = 21,
    stroke = 2,
    alpha = 0.35
  ) +
  
  geom_node_point(
    data = function(x) dplyr::filter(x, is_root),
    aes(size = size_plot),
    shape = 21,
    fill = "#6a3d9a",
    colour = "white",
    stroke = 2.2,
    alpha = 1
  ) +
  
  geom_node_point(
    data = function(x) dplyr::filter(x, !is_root),
    aes(size = size_plot, colour = score_polarizante),
    alpha = 0.95
  ) +
  
  # labels for non-root nodes (bigger text)
  geom_node_label(
    data = function(x) dplyr::filter(x, !is_root),
    aes(label = label, fill = score_polarizante),
    repel = TRUE,
    size = 4.8,                 # <- sube esto (antes 4.1)
    label.size = 0.25,
    label.padding = unit(0.24, "lines"),
    label.r = unit(0.18, "lines"),
    alpha = 0.92,
    lineheight = 1.0
  ) +
  
  # label for ROOT node (even bigger text)
  geom_node_label(
    data = function(x) dplyr::filter(x, is_root),
    aes(label = label),
    repel = TRUE,
    size = 5.4,                 # <- sube esto (antes 4.6)
    fill = "#6a3d9a",
    colour = "white",
    label.size = 0.35,
    label.padding = unit(0.30, "lines"),
    label.r = unit(0.22, "lines"),
    alpha = 0.98,
    lineheight = 1.0
  ) +
  
  scale_colour_gradientn(
    colours = pal,
    limits = c(0, lim_max),
    oob = squish,
    name = "Polarization"
  ) +
  scale_fill_gradientn(
    colours = pal,
    limits = c(0, lim_max),
    oob = squish,
    name = "Polarization"
  ) +
  scale_size_identity() +
  scale_edge_width_identity() +
  
  theme_void(base_size = 14) +
  theme(
    legend.position = "bottom",
    plot.margin = margin(12, 18, 12, 18),
    legend.title = element_text(size = 11),
    legend.text  = element_text(size = 10),
    plot.title = element_text(hjust = 0.5),
    plot.caption = element_text(size = 14, hjust = 0),  # <- bigger caption
    plot.caption.position = "plot"
  ) +
  labs(
    title = "Polarized Conversation About a Candidate’s Ideological Repositioning",
    subtitle = expression(italic("Comments translated from Spanish to English")), 
    caption = "Note. Nodes represent posts/comments and directed edges represent replies (parent → child).\nNode color and label fill indicate polarization intensity (score_polarizante), while edge width reflects the polarization score of the replying comment.\nThe central post is highlighted in purple, and the conflict subthread (c02–c07) is marked with a halo."
  )

p

# Optional export (taller figure)
ggsave("outputs/figures/reddit_network.png", p, width = 16, height = 12, dpi = 320)




