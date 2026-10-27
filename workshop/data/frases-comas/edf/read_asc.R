#rm(list = ls())
library(readxl)
library(tidyverse)
library(stringr)
#library(furrr)

# For experiments with many participants, you can use future_lapply to process them in parallel
#library(future.apply)
#plan("multisession")

# This uses code from Martin Vasilev's EMreading package: https://github.com/martin-vasilev/EMreading
# It was adapted to work with our EDF files
EMreading_path <- "edf/EMreading/"
EMreading_fixed_path <- "edf/EMreading_for_THE/"

# Specifically, the utility functions
source(paste0(EMreading_path, "utility.R"))
#source(paste0(EMreading_path, "utility_updated.R"))
# and the single line function
source(paste0(EMreading_fixed_path,"SingleLine_commas.R"))

source(paste0(EMreading_path,"cleanData.R"))

#source(paste0(EMreading_path,"cleanData_fixed.R"))

source(paste0(EMreading_path,"wordMeasures.R"))

#source(paste0(EMreading_path,"wordMeasures_for_singleLine.R"))

# these functions are specifically to make EMreading work with our files
#source(paste0(EMreading_path,"emReading_functions_for_OpenSesame_data.R"))

# read corpus data and prepare word-by-word data frame (actually tibble since we are using tidyverse)

# process_sentence_for_corpus <- function(corpus_row){
#   words <- with(corpus_row, paste(pretarget, target, posttarget, collapse = "")) %>% str_split(" ") %>% unlist() %>% # make a list of the words
#     enframe(name = "word", value = "string") %>% #then turn it into a tibble
#     mutate(target = string == corpus_row$target, pre_target = lead(target), post_target = lag(target), item = corpus_row$sentence_number, ben_fit_condition = corpus_row$ben_fit_condition) %>% 
#     replace_na(list(pre_target = FALSE, post_target = FALSE )) # remove NAs
#   return(words)
# }

sentences_commas <- read_excel("sentences_final.xlsx") %>% mutate(has_question = !is.na(question))

# If exist, remove all whitespaces before and after words

sentences <- sentences_commas %>% filter(sentence_number < 131) # extract the 130 experimental sentences
practice <- sentences_commas %>% filter(is.na(sentence_number))

sentences <- sentences %>% mutate(across(R1_original:R5_original, str_trim)) %>% unite(full_sentences_with_comma, R1_original:R5_original, sep = " ", remove = FALSE) %>% unite(full_sentences_with_comma_with_separators, ends_with("_original"), sep = " ^", remove = FALSE) %>% 
  mutate(across(R1_without:R5_without, str_trim)) %>% unite(full_sentences_without_comma, ends_with("_without"), sep = " ", remove = FALSE) %>% unite(full_sentences_without_comma_with_separators, ends_with("_without"), sep = " ^", remove = FALSE) %>%
  mutate(R0_cnt = 0, R1_cnt = R0_cnt + str_count(R1_original) + 1, R2_cnt = R1_cnt + str_count(R2_original) + 1, R3_cnt = R2_cnt + str_count(R3_original) + 1, R4_cnt = R3_cnt + str_count(R4_original) + 1, R5_cnt = R4_cnt + str_count(R5_original) + 1, R6_cnt = R5_cnt + 20) %>%
  mutate(R0_cntw = 0, R1_cntw = R0_cntw + str_count(R1_without) + 1, R2_cntw = R1_cntw + str_count(R2_without) + 1, R3_cntw = R2_cntw + str_count(R3_without) + 1, R4_cntw = R3_cntw + str_count(R4_without) + 1, R5_cntw = R4_cntw + str_count(R5_original) + 1, R6_cntw = R5_cntw + 20)


#practice <- practice %>% mutate(across(R1_original:R5_original, str_trim)) %>% unite(full_sentences_with_comma, R1_original:R5_original, sep = " ", remove = FALSE) %>% unite(full_sentences_with_comma_with_separators, ends_with("_original"), sep = " ^", remove = FALSE) %>% 
#  mutate(across(R1_without:R5_without, str_trim)) %>% unite(full_sentences_without_comma, ends_with("_without"), sep = " ", remove = FALSE) %>% unite(full_sentences_without_comma_with_separators, ends_with("_without"), sep = " ^", remove = FALSE) %>%
#  mutate(R0_cnt = 0, R1_cnt = R0_cnt + str_count(R1_original) + 1, R2_cnt = R1_cnt + str_count(R2_original) + 1, R3_cnt = R2_cnt + str_count(R3_original) + 1, R4_cnt = R3_cnt + str_count(R4_original) + 1, R5_cnt = R4_cnt + str_count(R5_original) + 1, R6_cnt = R5_cnt + 20) %>%
#  mutate(R0_cntw = 0, R1_cntw = R0_cntw + str_count(R1_without) + 1, R2_cntw = R1_cntw + str_count(R2_without) + 1, R3_cntw = R2_cntw + str_count(R3_without) + 1, R4_cntw = R3_cntw + str_count(R4_without) + 1, R5_cntw = R4_cntw + str_count(R5_original) + 1, R6_cntw = R5_cntw + 20)



sentences %>% count(sentence_type) # 26 sentences per type
sentences %>% filter(!is.na(answer)) %>% count(answer) # 17 yes / 17 no answers
 
sentence_table <- sentences %>% select(sentence_number, original_sentence, without_sentence) %>% pivot_longer(cols = c(original_sentence, without_sentence), names_to = "condition", values_to = "sentence") %>% mutate(condition = if_else(condition == "original_sentence",1,2))

# corpus <- read_csv("English sentence experiment.csv", col_types = cols(
#   sentence_number = col_double(),
#   preview_condition = col_double(),
#   ben_fit_condition = col_double(),
#   pretarget = col_character(),
#   target = col_character(),
#   posttarget = col_character(),
#   question = col_character(),
#   correct = col_character()
# )) %>%
#   split(.$sentence_number) %>%
#   purrr::map_dfr(.f = process_sentence_for_corpus)
# 



#files <- get_files(dir = "edf/", file_ext = ".asc$")

files <- "edf/E4L2.asc"
fix_measures_skip_all <- SingleLineCommas(data_list = files[1], ResX = 1920, ResY = 1080, textStim = sentence_table, ppl = 16, xOffset = 93)
#data_test <- lapply(files[5], FUN = process_file)

#clean_data_all <- future_lapply(files[5:22], FUN = process_file)

#clean_data_df <- do.call(rbind, clean_data_all)

#fix_measures_skip_all_test <- lapply(files[1], FUN = process_file, make_plot = TRUE)


#fix_measures_skip_all <- future_lapply(files, FUN = process_file, make_plot = TRUE)

save(fix_measures_skip_all, file = "fix_measures.RData")

#process_file(files[1], make_plot = TRUE)

stop("stop here")

fix_measures_skip_all_df <- do.call(rbind, fix_measures_skip_all)

to_csv <- fix_measures_skip_all_df %>% select(sub, item, FFD, SFD, GD, TVT, nfix1, nfix2, nfixAll, regress, string, target, pre_target, post_target, ben_condition, ben_fit_condition, correct, first_pass_skip)

write_csv(path = "ben_experiment_data_for_analysis_subj_104_to_121.csv", x= to_csv)

library(lme4)
library(lmerTest)

to_csv <- to_csv %>% mutate(ben_condition = factor(ben_condition), ben_fit_condition = factor(ben_fit_condition))

contrasts(to_csv$ben_condition) <- c(1, -1)

contrasts(to_csv$ben_fit_condition) <- c(-1, 1)

glmm1_pre <- glmer(data = to_csv, subset = pre_target, first_pass_skip ~ ben_condition * ben_fit_condition + (1|sub) + (1|item), family = binomial(link = "logit"))


glmm1 <- glmer(data = to_csv, subset = target, first_pass_skip ~ ben_condition * ben_fit_condition + (ben_condition|sub) + (ben_condition|item), family = binomial(link = "logit"))

lmm1 <- lmer(data = to_csv, subset = target, GD ~ ben_condition * ben_fit_condition + (ben_condition|sub) + (1|item))

lmm1_tvt <- lmer(data = to_csv, subset = target, TVT ~ ben_condition * ben_fit_condition + (1|sub) + (1|item))

lmm1_posttarget <- lmer(data = to_csv, subset = post_target, GD ~ ben_condition * ben_fit_condition + (1|sub) + (1|item))

glmm_pre <- glmer(data = to_csv, subset = pre_target, first_pass_skip ~ ben_condition * ben_fit_condition + (1|sub) + (1|item), family = binomial(link = "logit"))
