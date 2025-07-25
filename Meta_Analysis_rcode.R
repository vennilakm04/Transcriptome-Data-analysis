# Install and load required libraries
if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager")
if (!requireNamespace("multtest", quietly = TRUE)) BiocManager::install("multtest")
if (!requireNamespace("metap", quietly = TRUE)) install.packages("metap")
if (!requireNamespace("readxl", quietly = TRUE)) install.packages("readxl")
if (!requireNamespace("writexl", quietly = TRUE)) install.packages("writexl")
if (!requireNamespace("ggplot2", quietly = TRUE)) install.packages("ggplot2")

library(readxl)
library(dplyr)
library(writexl)
library(metap)
library(ggplot2)
library(ggrepel)

# Step 1: Define the folder path and list all Excel files
folder_path <- "C:/SASTRA/RNASeq project/GSEids_8"
file_names <- list.files(path = folder_path, pattern = "\\.xlsx$", full.names = TRUE)

# Step 2: Initialize lists to store data
all_data <- list()

# Step 3: Read and validate data from each file
for (file in file_names) {
  cat("Processing file:", file, "\n")
  
  # Read the data
  data <- read_excel(file)
  
  # Check for required columns
  if (!all(c("Geneid", "log2FoldChange", "padj") %in% colnames(data))) {
    warning("File ", file, " does not contain the required columns and will be skipped.")
    next
  }
  
  # Process the data
  data <- data %>% 
    mutate(Geneid = trimws(Geneid)) %>%  # Remove leading/trailing whitespace
    filter(!is.na(padj) & !is.na(log2FoldChange))  # Remove rows with NA values
  
  processed_data <- data.frame(
    Gene = data$Geneid,
    pvalue = as.numeric(data$padj),  # Ensure numeric format
    log2fc = as.numeric(data$log2FoldChange)
  )
  
  # Store the processed data
  all_data[[file]] <- processed_data
}

# Step 4: Check if any data was successfully loaded
if (length(all_data) < 1) {
  stop("No valid files found with the required columns. Please check your input files.")
}

# Step 5: Find common genes across all datasets
common_genes <- Reduce(intersect, lapply(all_data, function(df) df$Gene))
cat("Number of common genes:", length(common_genes), "\n")

if (length(common_genes) == 0) {
  stop("No common genes found across datasets. Please check input files.")
}

# Step 6: Standardize datasets for common genes
for (file in names(all_data)) {
  all_data[[file]] <- all_data[[file]] %>%
    filter(Gene %in% common_genes) %>%
    distinct(Gene, .keep_all = TRUE) %>%  # Remove duplicates
    arrange(Gene)  # Ensure same row order across datasets
}

# Step 7: Ensure matrices match common_genes
pvalues_list <- lapply(all_data, function(df) df$pvalue)
log2fc_list <- lapply(all_data, function(df) df$log2fc)

# Ensure that all vectors have the exact same length as common_genes
pvalues_list <- lapply(pvalues_list, function(p) {
  if (length(p) != length(common_genes)) stop("Mismatch detected in p-values!")
  return(p)
})

log2fc_list <- lapply(log2fc_list, function(fc) {
  if (length(fc) != length(common_genes)) stop("Mismatch detected in log2FC values!")
  return(fc)
})

# Combine matrices
pvalues <- do.call(cbind, pvalues_list)
log2fc <- do.call(cbind, log2fc_list)

# Assign row names to match common_genes
rownames(pvalues) <- common_genes
rownames(log2fc) <- common_genes

# Debugging checks
cat("Final dimensions of pvalues matrix:", dim(pvalues), "\n")
cat("Final dimensions of log2fc matrix:", dim(log2fc), "\n")


# Step 8: Perform meta-analysis using Fisher's method
combined_pvalues <- apply(pvalues, 1, function(p) {
  p <- as.numeric(na.omit(p))  # Convert to numeric and remove NA values
  p <- p[p > 0 & p <= 1]  # Ensure valid p-values
  
  if (length(p) > 1) {
    sumlog(p)$p  # Fisher's method
  } else if (length(p) == 1) {
    p  # Single valid p-value
  } else {
    NA  # No valid p-values
  }
})

# Calculate mean log2 fold changes
mean_log2fc <- rowMeans(log2fc, na.rm = TRUE)

# Step 9: Combine results into a data frame
meta_results <- data.frame(
  Gene = common_genes,
  Combined_Pvalue = combined_pvalues,
  Mean_Log2FC = mean_log2fc
)

# Step 10: Save the results to an Excel file
output_path <- "C:/SASTRA/RNASeq project/GSEids_8/metaRNASeq_result_all.xlsx"
write_xlsx(meta_results, output_path)
cat("Meta-analysis results saved to:", output_path, "\n")
print(head(meta_results))

# Step 11: Add a significance column
meta_results <- meta_results %>%
  mutate(Significance = ifelse(
    Combined_Pvalue < 0.05 & (Mean_Log2FC) < -2,  # Adjust thresholds as needed
    "Significant",
    "Not Significant"
  ))

# Step 12: Visualization - Volcano Plot with Gene Names
volcano_plot <- ggplot(meta_results, aes(x = Mean_Log2FC, y = -log10(Combined_Pvalue), color = Significance)) +
  geom_point(alpha = 0.7, size = 2) +
  scale_color_manual(
    values = c("Significant" = "red", "Not Significant" = "grey"),
    name = "Gene Significance"
  ) +
  geom_text_repel(
    data = subset(meta_results, Significance == "Significant"),
    aes(label = Gene),
    size = 3,
    box.padding = 0.3,
    point.padding = 0.3,
    max.overlaps = 20
  ) +
  labs(
    title = "Volcano Plot of Meta-Analysis Results",
    x = "Mean Log2 Fold Change",
    y = "-log10(Combined P-value)"
  ) +
  theme_minimal() +
  theme(legend.position = "right")

# Display the plot
print(volcano_plot)

# Save the volcano plot
ggsave(
  filename = "C:/SASTRA/RNASeq project/GSEids_8/negative_plot_with_labels.png",
  plot = volcano_plot,
  width = 8, height = 6, dpi = 300
)

# Step 13: Extract Significant Genes
significant_genes <- meta_results %>%
  filter(Significance == "Significant")

# Step 14: Save Significant Genes
significant_output_path <- "C:/SASTRA/RNASeq project/GSEids_8/-ve_significant_genes.xlsx"
write_xlsx(significant_genes, significant_output_path)
cat("Significant genes saved to:", significant_output_path, "\n")
print(head(significant_genes))

# Step 15: Save Common Genes
common_genes_df <- data.frame(Gene = common_genes)
write_xlsx(common_genes_df, "C:/SASTRA/RNASeq project/GSEids_8/common_genes.xlsx")

cat("Analysis completed successfully! 🎉\n")
