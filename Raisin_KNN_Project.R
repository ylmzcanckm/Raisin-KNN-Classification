# Raisin Variety Classification with K-Nearest Neighbors (KNN)
#
# This script performs exploratory data analysis, prepares the data,
# tunes the K value on a validation set, evaluates the final KNN model,
# and saves all tables and visualizations to the outputs/ directory.

required_packages <- c("tidyverse", "readxl", "caTools", "class")
new_packages <- required_packages[
  !(required_packages %in% rownames(installed.packages()))
]

if (length(new_packages) > 0) {
  install.packages(new_packages, dependencies = TRUE)
}

library(tidyverse)
library(readxl)
library(caTools)
library(class)

dir.create("data", showWarnings = FALSE)
dir.create("outputs", showWarnings = FALSE)

csv_path <- file.path("data", "raisin_dataset.csv")

# Use the included CSV when available. Otherwise, download the original
# dataset from the UCI Machine Learning Repository.
if (file.exists(csv_path)) {
  raisin_raw <- read_csv(csv_path, show_col_types = FALSE)
} else {
  zip_path <- file.path("data", "raisin.zip")

  download.file(
    "https://archive.ics.uci.edu/static/public/850/raisin.zip",
    zip_path,
    mode = "wb"
  )

  unzip(zip_path, exdir = "data")

  nested_zip_files <- list.files(
    "data",
    pattern = "\\.zip$",
    recursive = TRUE,
    full.names = TRUE,
    ignore.case = TRUE
  )

  nested_zip_files <- nested_zip_files[
    basename(nested_zip_files) != basename(zip_path)
  ]

  if (length(nested_zip_files) > 0) {
    for (nested_zip in nested_zip_files) {
      unzip(nested_zip, exdir = dirname(nested_zip))
    }
  }

  xlsx_files <- list.files(
    "data",
    pattern = "\\.xlsx$",
    recursive = TRUE,
    full.names = TRUE,
    ignore.case = TRUE
  )

  if (length(xlsx_files) == 0) {
    stop("Raisin dataset Excel file could not be found.")
  }

  raisin_raw <- read_excel(xlsx_files[1])
  write_csv(raisin_raw, csv_path)
}

# 1. Data quality checks and preparation
missing_summary <- tibble(
  variable = names(raisin_raw),
  missing_count = colSums(is.na(raisin_raw))
)

write_csv(
  missing_summary,
  file.path("outputs", "01_missing_values_summary.csv")
)

raisin <- raisin_raw %>%
  distinct() %>%
  mutate(Class = as.factor(Class))

class_distribution <- raisin %>%
  count(Class) %>%
  mutate(percentage = round(100 * n / sum(n), 2))

write_csv(
  class_distribution,
  file.path("outputs", "02_class_distribution.csv")
)

p_class <- ggplot(class_distribution, aes(x = Class, y = n, fill = Class)) +
  geom_col(width = 0.65) +
  geom_text(aes(label = n), vjust = -0.4) +
  labs(
    title = "Distribution of Raisin Varieties",
    x = "Raisin Variety",
    y = "Number of Observations"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

ggsave(
  file.path("outputs", "03_class_distribution.png"),
  p_class,
  width = 7,
  height = 5
)

# 2. Exploratory data analysis
numeric_data <- raisin %>%
  select(where(is.numeric))

descriptive_statistics <- numeric_data %>%
  summarise(
    across(
      everything(),
      list(
        mean = ~ mean(.x, na.rm = TRUE),
        median = ~ median(.x, na.rm = TRUE),
        sd = ~ sd(.x, na.rm = TRUE),
        min = ~ min(.x, na.rm = TRUE),
        max = ~ max(.x, na.rm = TRUE)
      )
    )
  ) %>%
  pivot_longer(
    cols = everything(),
    names_to = c("variable", ".value"),
    names_pattern = "(.*)_(mean|median|sd|min|max)"
  )

write_csv(
  descriptive_statistics,
  file.path("outputs", "04_descriptive_statistics.csv")
)

p_hist <- ggplot(raisin, aes(x = Area, fill = Class)) +
  geom_histogram(bins = 30, alpha = 0.65, position = "identity") +
  labs(
    title = "Distribution of Area by Raisin Variety",
    x = "Area",
    y = "Frequency"
  ) +
  theme_minimal()

ggsave(
  file.path("outputs", "05_area_histogram.png"),
  p_hist,
  width = 7,
  height = 5
)

raisin_long <- raisin %>%
  pivot_longer(
    cols = where(is.numeric),
    names_to = "Feature",
    values_to = "Value"
  )

p_box <- ggplot(raisin_long, aes(x = Class, y = Value, fill = Class)) +
  geom_boxplot(outlier.alpha = 0.35) +
  facet_wrap(~ Feature, scales = "free_y") +
  labs(
    title = "Morphological Features by Raisin Variety",
    x = "Raisin Variety",
    y = "Value"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

ggsave(
  file.path("outputs", "06_feature_boxplots.png"),
  p_box,
  width = 11,
  height = 7
)

p_scatter <- ggplot(raisin, aes(x = Area, y = Perimeter, color = Class)) +
  geom_point(alpha = 0.65) +
  labs(
    title = "Area vs Perimeter by Raisin Variety",
    x = "Area",
    y = "Perimeter"
  ) +
  theme_minimal()

ggsave(
  file.path("outputs", "07_area_vs_perimeter.png"),
  p_scatter,
  width = 7,
  height = 5
)

correlation_matrix <- cor(numeric_data, method = "pearson")

write.csv(
  round(correlation_matrix, 3),
  file.path("outputs", "08_correlation_matrix.csv"),
  row.names = TRUE
)

png(
  file.path("outputs", "09_correlation_heatmap.png"),
  width = 1100,
  height = 900
)

heatmap(
  correlation_matrix,
  Rowv = NA,
  Colv = NA,
  scale = "none",
  margins = c(10, 10),
  main = "Correlation Heatmap of Numerical Features"
)

dev.off()

# 3. Stratified train, validation, and test split
set.seed(123)

split_train <- sample.split(raisin$Class, SplitRatio = 0.70)
train <- subset(raisin, split_train == TRUE)
remaining <- subset(raisin, split_train == FALSE)

split_validation <- sample.split(remaining$Class, SplitRatio = 0.50)
validation <- subset(remaining, split_validation == TRUE)
test <- subset(remaining, split_validation == FALSE)

split_summary <- tibble(
  dataset = c("Training", "Validation", "Test"),
  rows = c(nrow(train), nrow(validation), nrow(test))
)

write_csv(
  split_summary,
  file.path("outputs", "10_split_summary.csv")
)

# 4. Feature scaling and K tuning
predictors <- setdiff(names(raisin), "Class")

train_scaled <- scale(train[predictors])
training_center <- attr(train_scaled, "scaled:center")
training_scale <- attr(train_scaled, "scaled:scale")

validation_scaled <- scale(
  validation[predictors],
  center = training_center,
  scale = training_scale
)

k_values <- seq(1, 25, by = 2)

validation_results <- map_dfr(k_values, function(k_value) {
  predicted_class <- knn(
    train = train_scaled,
    test = validation_scaled,
    cl = train$Class,
    k = k_value
  )

  tibble(
    k = k_value,
    validation_accuracy = mean(predicted_class == validation$Class)
  )
})

write_csv(
  validation_results,
  file.path("outputs", "11_k_validation_results.csv")
)

best_k <- validation_results %>%
  arrange(desc(validation_accuracy), k) %>%
  slice(1) %>%
  pull(k)

p_k <- ggplot(validation_results, aes(x = k, y = validation_accuracy)) +
  geom_line() +
  geom_point() +
  scale_x_continuous(breaks = k_values) +
  labs(
    title = "Validation Accuracy for Different K Values",
    x = "K Value",
    y = "Validation Accuracy"
  ) +
  theme_minimal()

ggsave(
  file.path("outputs", "12_k_validation_accuracy.png"),
  p_k,
  width = 7,
  height = 5
)

# 5. Final model and test-set evaluation
final_train <- bind_rows(train, validation)
final_train_scaled <- scale(final_train[predictors])
final_center <- attr(final_train_scaled, "scaled:center")
final_scale <- attr(final_train_scaled, "scaled:scale")

test_scaled <- scale(
  test[predictors],
  center = final_center,
  scale = final_scale
)

test_pred <- knn(
  train = final_train_scaled,
  test = test_scaled,
  cl = final_train$Class,
  k = best_k
)

actual <- test$Class
confusion_matrix <- table(Actual = actual, Predicted = test_pred)

write.csv(
  as.data.frame.matrix(confusion_matrix),
  file.path("outputs", "13_confusion_matrix.csv"),
  row.names = TRUE
)

positive_class <- "Besni"
tp <- confusion_matrix[positive_class, positive_class]
fp <- sum(confusion_matrix[, positive_class]) - tp
fn <- sum(confusion_matrix[positive_class, ]) - tp
tn <- sum(confusion_matrix) - tp - fp - fn

accuracy <- (tp + tn) / sum(confusion_matrix)
precision <- tp / (tp + fp)
recall <- tp / (tp + fn)
f1_score <- 2 * precision * recall / (precision + recall)

evaluation_metrics <- tibble(
  metric = c("Best K", "Accuracy", "Precision", "Recall", "F1 Score"),
  value = c(best_k, accuracy, precision, recall, f1_score)
)

write_csv(
  evaluation_metrics,
  file.path("outputs", "14_model_evaluation_metrics.csv")
)

prediction_results <- test %>%
  mutate(Predicted_Class = test_pred)

write_csv(
  prediction_results,
  file.path("outputs", "15_test_predictions.csv")
)

print(confusion_matrix)
print(evaluation_metrics)
