library(tidyverse)

# Define the file path
file_path <- "./edf/C1L1.asc"


read_asc_file_accuracy <- function(file_name){
  
  # Read the entire file into a character vector
  my_vector <- readLines(file_name)
  
  # Filter out the relevant lines using vectorized commands
  my_vector <- my_vector[grepl("^MSG\\s+\\d{6,10}\\s+(TRIALID|QUESTION_ANSWER|TRIAL_RESULT)\\s+", my_vector)]
  
  # Split the vector into trials
  trial_starts <- which(grepl("^MSG\\s+\\d{6,10}\\s+TRIALID\\s+E", my_vector))
  trial_ends <- c(trial_starts[-1] - 1, length(my_vector))
  trials <- lapply(seq_along(trial_starts), function(i) my_vector[trial_starts[i]:trial_ends[i]])
  
  # Create a data frame with the E TRIALID and whether the trial was correct or not
  df <- data.frame(file_name = character(),
                   itemnr = character(),
                   condition = character(),
                   dependent = character(),
                   correct = logical(),
                   stringsAsFactors = FALSE)
  
  for (i in seq_along(trials)) {
    if (grepl("^MSG\\s+\\d{6,10}\\s+TRIALID\\s+E", trials[[i]][1])) {
      e_id <- gsub("^MSG\\s+\\d{6,10}\\s+TRIALID\\s+", "", trials[[i]][1])
      condition <- gsub("^E(.).*I.*D.*", "\\1", e_id)
      itemnr <- gsub("^.*I(.*?)D.*$", "\\1", e_id)
      dependent <- gsub("^.*D(.*)$", "\\1", e_id)
      correct <- NA
      
      if (length(trials[[i]]) > 2) {
        qa_result <- as.numeric(gsub("^MSG\\s+\\d{6,10}\\s+QUESTION_ANSWER\\s+", "", trials[[i]][4]))
        tr_result <- as.numeric(gsub("^MSG\\s+\\d{6,10}\\s+TRIAL_RESULT\\s+", "", trials[[i]][5]))
        correct <- qa_result == tr_result
      }
      
      df[nrow(df) + 1, ] <- list(file_name, itemnr, condition, dependent, correct)
      
    }
  }
  return(df)
}

file_list <- paste0("./edf/", dir(path = "./edf", pattern = glob2rx("*.asc")))

df_list <- list()
for (filename in file_list) {
  cat(filename, "\n")
  df_list[[filename]] <- read_asc_file_accuracy(filename)
}

df_combined <- do.call(rbind, df_list)

df_combined$condition <- factor(df_combined$condition, levels = c(1,2), labels = c("comma", "no comma"))

write_csv(df_combined, file = "accuracy_by_subject_item_condition.csv")

library(brms)

contrasts(df_combined$condition) <- contr.sum

priors_acc <-  set_prior("normal(0,100)", class = "b")


acc_blm <- brm(data = df_combined, 
                 correct ~ condition + (condition|file_name) + (condition|itemnr), 
                 family = bernoulli,
                 prior = priors_acc,
                 iter = 5000)

overall_means <- df_combined %>% filter(!is.na(correct)) %>% 
  group_by(condition) %>%
  summarize(accuracy = mean(correct))

means_by_participant <- df_combined %>% filter(!is.na(correct)) %>% 
  group_by(file_name) %>%
  summarize(accuracy = mean(correct))

load("accuracy_brms_summary.RData")
