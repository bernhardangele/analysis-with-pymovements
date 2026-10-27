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
 
sentence_table <- sentences %>% select(sentence_number, original_sentence, without_sentence, sentence_type) %>% pivot_longer(cols = c(original_sentence, without_sentence), names_to = "condition", values_to = "sentence") %>% mutate(condition = if_else(condition == "original_sentence",1,2))

prepare_data_frame <-  function(ixs){
  ixs %>% filter(cond != 0) %>% left_join(sentence_table, by = c("item" = "sentence_number", "cond" = "condition")) %>% mutate(comma_cond = factor(cond, levels = c(1,2), labels = c("comma", "no_comma")) %>%  `contrasts<-`(., value = c(-.5,.5)))
}


FFD <- read_csv("edf/FFDW.IXS") %>% prepare_data_frame()
GD <- read_csv("edf/GD.IXS") %>% prepare_data_frame()
GP <- read_csv("edf/GOPAST.IXS") %>% prepare_data_frame()
TVT <- read_csv("edf/TVT.IXS") %>% prepare_data_frame()

global_fix <- TVT %>% group_by(subj, item, sentence_type, comma_cond) %>%  summarise(datum = sum(datum, na.rm = TRUE))

save(FFD,GD,GP,TVT,global_fix, file = "comma_eye_movement_measures.RData")

library(lme4)

lmer_tvalue <- function(df){
  model <- lmer(data = df, log(datum) ~ comma_cond + (1|subj) + (1|item))
  # return the t-value
  model %>% summary %>% coef %>% as_tibble %>% .$`t value` %>% .[2]
}

t_values_FFD <- FFD %>% filter(datum < 800 & region < 6) %>%
  group_by(region, sentence_type) %>%
  do(t_value = lmer_tvalue(.))
     
efecto_coma_FFD <- FFD %>% filter(datum < 800 & region < 6) %>%
  group_by(region, sentence_type ) %>%
  do(efecto = mean(filter(., comma_cond == "comma")$datum, na.rm = TRUE) - mean(filter(., comma_cond == "no_comma")$datum, na.rm = TRUE))

t_values_FFD$efecto <- efecto_coma_FFD$efecto

t_values_GD <- GD %>% filter(datum < 1500 & region < 6) %>%
  group_by(region, sentence_type) %>%
  do(t_value = lmer_tvalue(.))
 
t_values_TVT <- TVT %>% filter(datum < 1500 & region < 6) %>%
  group_by(region, sentence_type) %>%
  do(t_value = lmer_tvalue(.))

t_values_GP <- GP %>% filter(datum < 2000 & region < 6) %>%
  group_by(region, sentence_type) %>%
  do(t_value = lmer_tvalue(.))

t_values_global <- global %>%
  group_by(sentence_type) %>%
  do(t_value = lmer_tvalue(.))

t_values <- t_values_FFD
t_values$GD <- t_values_GD$t_value
t_values$TVT <- t_values_TVT$t_value
t_values$GP <- t_values_GP$t_value


lm.ffd.pre <- lmer(data = FFD %>% filter(datum < 800 & region == 2), datum ~ comma_cond + (1|subj) + (1|item))
lm.ffd.comma <- lmer(data = FFD %>% filter(datum < 800 & region == 3), datum ~ comma_cond + (1|subj) + (1|item))
lm.ffd.post <- lmer(data = FFD %>% filter(datum < 800 & region == 4), datum ~ comma_cond + (1|subj) + (1|item))

lm.gd.pre <- lmer(data = GD %>% filter(datum < 1200 & region == 2), datum ~ comma_cond + (1|subj) + (1|item))
lm.gd.comma <- lmer(data = GD %>% filter(datum < 1200 & region == 3), datum ~ comma_cond + (1|subj) + (1|item))
lm.gd.post <- lmer(data = GD %>% filter(datum < 1200 & region == 4), datum ~ comma_cond + (1|subj) + (1|item))

lm.gp.pre <- lmer(data = GP %>% filter(datum < 2500 & region == 2), datum ~ comma_cond + (1|subj) + (1|item))
lm.gp.comma <- lmer(data = GP %>% filter(datum < 2500 & region == 3), datum ~ comma_cond + (1|subj) + (1|item))
lm.gp.post <- lmer(data = GP %>% filter(datum < 2500 & region == 4), datum ~ comma_cond + (1|subj) + (1|item))

lm.tvt.pre <- lmer(data = TVT %>% filter(datum < 2500 & region == 2), datum ~ comma_cond + (1|subj) + (1|item))
lm.tvt.comma <- lmer(data = TVT %>% filter(datum < 2500 & region == 3), datum ~ comma_cond + (1|subj) + (1|item))
lm.tvt.post <- lmer(data = TVT %>% filter(datum < 2500 & region == 4), datum ~ comma_cond + (1|subj) + (1|item))

lmm.global <- lmer(data = global, datum ~ comma_cond + (1|subj) + (1|item))
