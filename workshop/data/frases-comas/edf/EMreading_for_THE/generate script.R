rm(list = ls())

library(tidyverse)

sent <- read_csv("Turkish Sentences.csv")

test = TRUE # use mouse instead of gamepad

number_of_conditions <- 4

number_of_experiments <- 1


response_sentences <- ifelse(test, "mouse", "toggle")

response_questions <- ifelse(test, "mouse", c("leftTrigger","rightTrigger"))

trigger_sentences <- ifelse(0, "nogaze", "driftandgaze")


preamble <- str_c("%BeginHeader",
                  "Eyetrack reading experiment with noise by Bernhard Angele",
                  "output from writeexp.m",
                  "%EndHeader",
                  "",
                  str_glue("set conditions = {number_of_conditions}"),
                  str_glue("set experiments = {number_of_experiments}"),
                  "set background =  16777215", # white
                  "set foreground =  0", # black
                  "set filterMode = 2",
                  "set windowThreshold = 0",
                  "set calibration_type = 0",
                  "set display_type = LCD",
                  sep = "\n"
)


gc_rect <- c(425, 40, 475, 90)

write_trial_type <- function(trial_type = "sentence", response = c("X","Y"), trigger = "nogaze", 
                             font = "Courier New", 
                             fontsize = 14,
                             linespace = 24,
                             x_offset = 50,
                             y_offset = 512
){
  
  paste(str_glue("trial_type {trial_type}"),
        str_glue("text_format =    '{font}' {fontsize} {linespace} {x_offset} {y_offset} antialiased"),
        paste(str_glue("button =         {response}"), collapse = "\n"),
        "output =         stream",
        str_glue("trigger =        {trigger}"),
        "cursor_size =    0",
        "revert = 0",
        str_glue("end {trial_type}"),
        sep = "\n")
}

conditions <- rep(1:4, 100)

practice_conditions <- 1

items <- rep(1:100, each = 4)

practice_items <- 1:10

trial_codes <- str_glue("E{conditions}I{items}D0")
practice_trial_codes <- str_glue("P{practice_conditions}I{practice_items}D0")

write_image_trial <- function(trial_codes, 
                              trial_type = "sentence", 
                              gc_rect = c(0,0,10,10),
                              max_display_time = 90000){
  str_c(str_glue("trial {trial_codes}"),
        str_glue("image = '{trial_codes}.BMP3'"),
        str_glue("gc_rect =          ({gc_rect[1]} {gc_rect[2]} {gc_rect[3]} {gc_rect[4]})"),
        str_glue("max_display_time = {max_display_time}"),
        str_glue("trial_type =       {trial_type}"),
        str_glue("end {trial_codes}"),
        sep = "\n", collapse = "\n\n")
}

conditions_question_trials <- rep(1:4, nrow(stimuli_with_questions))

conditions_questions <- with(stimuli_with_questions,if_else(str_to_lower(Answer) == "yes", 11, 12))
buttons_questions <- with(stimuli_with_questions,if_else(str_to_lower(Answer) == "yes", "leftTrigger", "rightTrigger"))


question_codes  <- str_glue("F{conditions_questions}I{stimuli_with_questions$trialnr}D1")

practice_question_trials <- 1:5
practice_question_codes <- str_glue("P1I{practice_question_trials}D1")

write_question_trial <- function(trial_codes, 
                                 trial_type = "question",
                                 text = "Did you understand the sentence?",
                                 gc_rect = c(0,0,10,10),
                                 max_display_time = 90000,
                                 button = "leftTrigger"
){
  str_c(str_glue("trial {trial_codes}"),
        #str_glue("button =            {button}"),
        str_glue("gc_rect =          ({gc_rect[1]} {gc_rect[2]} {gc_rect[3]} {gc_rect[4]})"),
        str_glue("inline =           |{text}\\nYes                                 No\\n\\n"),
        str_glue("max_display_time = {max_display_time}"),
        str_glue("trial_type =       {trial_type}"),
        str_glue("end {trial_codes}"),
        sep = "\n", collapse = "\n\n")
}

sequence_codes <- str_glue("SE{conditions_question_trials}I{rep(stimuli_with_questions$trialnr, each = number_of_conditions)}")

practice_sequence_codes <- str_glue("SP1I{1:5}")


trials_with_question_codes <- str_glue("E{conditions_question_trials}I{rep(stimuli_with_questions$trialnr, each = number_of_conditions)}D0")


write_sequence <- function(sequence_codes, trials_with_question_codes, question_codes)
{
  str_c(str_glue("sequence {sequence_codes}"),
        str_glue("  {trials_with_question_codes}"),
        str_glue("  {question_codes}"),
        str_glue("end {sequence_codes}"),
        sep = "\n", collapse = "\n\n")
}

experiment <- str_c(preamble, 
                    #write_trial_type(trial_type = 'practice', response = response_sentences, trigger = trigger_sentences),
                    write_trial_type(trial_type = 'sentence', response = response_sentences, trigger = trigger_sentences),
                    write_trial_type(trial_type = 'question', response = response_sentences, trigger= "nogaze", y_offset =320, fontsize = 16),
                    #write_trial_type(trial_type = 'practice', response = response_sentences), trigger = trigger_sentences),
                    write_image_trial(practice_trial_codes, trial_type = 'sentence', gc_rect),
                    write_question_trial(practice_question_codes, trial_type = 'question', text = practice$Question[1:5]),
                    write_image_trial(trial_codes, trial_type = 'sentence', gc_rect),
                    write_question_trial(question_codes, trial_type = 'question', text = stimuli_with_questions$Question, gc_rect, button = buttons_questions),
                    write_sequence(sequence_codes, trials_with_question_codes, rep(question_codes, each = number_of_conditions)),
                    write_sequence(practice_sequence_codes, practice_trial_codes[1:5], practice_question_codes),
                    sep = "\n\n")


cat(experiment, file = "ben_experiment.script")
