## all the functions that were modified in order to read opensesame experiments. Load after EMreading


get_num <-
  function(string) {
    as.numeric(unlist(gsub("[^0-9]", "", unlist(string)), ""))
  }

parse_itemID_ben_experiment <- function(trials) {
  # need to replace this for our trial pattern
  # the item ID parsing function might be added as an argument to trial_info in the future
  # this function needs to return a vector with the trial type (E, F, P), condition (seems to only allow numbers), item number, and whether it is a dependent trial or not (only important for Eyetrack)
  
  # use tidyr to extract all the variables in one go
  item_ID_data <-
    tidyr::extract(
      tibble(trial_code = trials),
      col = trial_code,
      into = c("item", "cond"),
      regex = "I([0-9]*)C_(\\w*)",
      convert = TRUE
    )
  
  E <- ifelse(item_ID_data$item < 900, "E", "P")
  cond <- ifelse(item_ID_data$cond == "identical", 1, 2)
  depend <-
    0 # none of the trials in this experiment are dependent trials
  
  return(c(E, cond, item_ID_data$item, depend))
  
}

# make our own get_text function

get_text <-
  function(file_lines) {
    ## extracts the loaded text material                         #
    
    text <-
      grep("TRIAL ", current_file[trial_db$ID[j]:trial_db$start[j]], value = TRUE)
    return(text)
    
  }


trial_info <-
  function(file,
           maxtrial,
           trial_flag = "TRIALID",
           trial_start_flag = "SYNCTIME",
           selectEXP = TRUE,
           parse_itemID = function(trials) {
             I <- unlist(gregexpr(pattern = 'I', trials)) # start of item info
             cond <-
               as.numeric(substr(trials, 2, I - 1)) # extract condition number
             
             ### get item:
             D <-
               unlist(gregexpr(pattern = 'D', trials)) # start of dependent info
             item <-
               as.numeric(substr(trials, I + 1, D - 1)) # extract condition number
             depend <-
               as.numeric(substr(trials, nchar(trials), nchar(trials)))
             
             # get letter:
             E <- substr(trials, 1, 1)
             
             return(c(E, cond, item, depend))
           }) {
    # get the trial ID stamps
    
    #trial_time<- which(grepl(trial_flag, file, perl = TRUE)) # the trial unfortunately starts with several TRIAL flags. Get the first one for the start time
    trial_text <- file[which(grepl(trial_flag, file))]
    trials <-
      substr(trial_text, unlist(gregexpr(pattern = ' ', trial_text[1]))[2] +
               1, nchar(trial_text))
    trials <- gsub(" ", "", trials)
    
    start_time <- which(grepl(trial_start_flag, file))
    
    
    # it's easier to get trial end time since some trial start information is missing for the practice trials
    # but sometimes the timing is off and the trial ends *after* the information about the next sentence is written to the EDF file!
    end_time <- grep("stop_trial", file)
    #end_time <- grep("end", file)
    
    trial_time <- c(1, end_time[-NROW(end_time)])
    
    
    # if there is no trial start flag, use trial ID flag:
    if (length(start_time) == 0) {
      start_time = trial_time
    }
    
    ### parse trials (takes care of duplicates, aborted trials, etc.):
    if (length(start_time) != length(trial_time)) {
      # mismatch problems..
      all <- NULL
      for (k in 1:length(trial_time)) {
        t <- which(trial_time[k] < start_time & end_time[k] > start_time)
        if (length(t) > 0) {
          all <- c(all, k)
        } else{
          #print(k)
        }
        #
      }
      trial_time = trial_time[all]
      end_time = end_time[all]
      trials = trials[all]
    }
    
    trial_db <- NULL
    
    for (i in 1:length(trials)) {
      v = parse_itemID(trials[i])
      #cat(v, "\n")
      temp <-
        tibble(
          cond = v[2],
          item = v[3],
          depend = v[4],
          E = v[1],
          start = start_time[i],
          end = end_time[i],
          ID = trial_time[i],
          stamp = trials[i],
          keep = 1
        )
      temp$stamp <- as.character(temp$stamp)
      temp$item <- as.numeric(as.character(temp$item))
      temp$cond <- as.numeric(as.character(temp$cond))
      temp$depend <- as.numeric(as.character(temp$depend))
      temp$E <- as.character(temp$E)
      
      dupl <- which(trial_db$stamp == temp$stamp)
      if (length(dupl) > 0) {
        trial_db$keep[dupl] = 0
        message(
          paste(
            " Duplicated trial ",
            temp$stamp,
            "! ",
            "Analysing only last attempt at the trial!",
            "\n",
            sep = ""
          )
        )
      }
      
      trial_db <- rbind(trial_db, temp)
    }
    
    # if all item numbers are NAs, use trial stamp instead:
    howManyNAs <- length(which(is.na(trial_db$item)))
    if (howManyNAs == nrow(trial_db)) {
      trial_db$item <- trial_db$stamp
    }
    
    
    if (!selectEXP) {
      # keep only questions
      trial_db <-
        subset(trial_db, depend > 0 & item < maxtrial + 1)#, keep==1
      trial_db <- subset(trial_db, E == "F")
    } else{
      # keep only experimental items
      if (howManyNAs != nrow(trial_db)) {
        # continue only if we use Eyetrack convention
        trial_db <-
          subset(trial_db, depend == 0 & item < maxtrial + 1)#, keep==1)
        trial_db <- subset(trial_db, E == "E")
        trial_db$depend <- NULL
      }
      
    }
    
    
    trial_db$seq <- 1:nrow(trial_db)
    
    trial_db$E <- NULL
    trial_db$stamp <- NULL
    
    trial_db <- subset(trial_db, keep == 1)
    trial_db$keep <- NULL
    
    
    return(trial_db)
    
  }

get_OpenSesame_info <- function(file) {
  os_data <-
    grep(x = file,
         pattern = " var ",
         value = TRUE) %>% # get all lines with variables
    tibble(text = .) %>% # extract only works on data frames (or tibbles)
    tidyr::extract(text, c("variable", "value"), regex = "MSG\\t[0-9]* var (\\w*) ([a-zA-Z0-9\\.\\?]*)") %>% # split text into columns
    .[-1, ] %>% # for some reason, the very first variable (eye_used) only appears in the very first trial, so we remove that row. This may break for other data sets``
    mutate(new_trial = variable == .$variable[1],
           trial = cumsum(new_trial)) %>% # now look for the first time a variable repeats. That shows us there is a new trial and so we can assign trials to the variables
    select(-new_trial) %>%
    group_by(trial) %>%
    spread(key = "variable",
           value = "value",
           convert = TRUE)
  
  return(os_data)
}

get_text <- function(file_lines) {
  grep("TRIAL ", file_lines, value = TRUE)
}

get_coord <- function(text,
                      x_offset = 75,
                      screen_height = 768) {
  # get all the information in the text at once using extract from tidyr. However, extract needs a dataframe or tibble as input, so we make it here
  words <-
    tidyr::extract(
      tibble(text = text),
      text,
      c("word", "string", "x2"),
      regex = "MSG\\t[0-9]* TRIAL [0-9]* ITEM [0-9]* WORD ([0-9]*) ([\\w\\?\\.'\\,-]*) RIGHT_BOUNDARY ([0-9]*)",
      convert = TRUE
    ) # need to include any kind of special characters that can appear in a word (.?,' etc.)
    out <- words %>% mutate(x1 = lag(x2),
           pix_per_char = (max(.$x2) - x_offset) / nchar(paste(.$string, collapse = " "))) %>% # get an estimate of how many pixels per character by dividing the distance between the x offset and the right boundary of the last word by the number of characters (including spaces)
    mutate(
      x1 = ifelse(word == 1, x_offset, x1), # ceiling(x1 + pix_per_char + 1)),
      # for the first word, x1 should be the x-offset. For all other words, make sure to account for the space (which should be as wide as any other character, at least for a monospace font)
      y1 = 0,
      y2 = screen_height,
      word_length = nchar(.$string) + ifelse(.$word == 1, 0, 1)
    ) %>% # add space before word
    group_by(word) %>%
    nest() %>%
    mutate(
      data = purrr::map(
        data,
        split_word_coordinates_into_letter_coordinates,
        screen_height, x_offset
      )
    ) %>%
    unnest(cols = c(data)) %>%
    mutate(word_line = word)
  

  # map characters per line (for Eye Doctor):
  out$line_char <- NA
  unq_line <- unique(out$line)
  for (i in 1:length(unq_line)) {
    line <- which(out$line == unq_line[i])
    out$line_char[line[1]:line[length(line)]] <- 1:length(line)
  }
  
  out$char <- out$line_char # counts characters total. Since we only have one line, this is the same as line_char
  
  column_order <-
    c("char", 
      "letter",
      "x1",
      "y1",
      "x2",
      "y2",
      "space",
      "sent",
      "line",
      "word", # counts characters within each word. Starts at 1 for each word
      "char_word",
      "word_line",
      "line_char") # counts characters within each line
  out <- out[, column_order]
  
  out <- out %>% left_join(words, suffix = c("", ".y"), by = "word") %>% mutate(wordID = string) %>% select(-string, -ends_with(".y"))

  return(out)
}

split_word_coordinates_into_letter_coordinates <-
  function(coords, screen_height = 768, x_offset = xOffset) {
    # takes a data frame with exactly one line
    if (nrow(coords) > 1) {
      warning(
        "split_word_coordinates_into_letter_coordinates: input has too many rows. This function takes a data frame with exactly one line. Using only the first line."
      )
      coords <- coords[1, ]
    }

    current_word <- coords$string
    
    
    
    letters <- c(" ", strsplit(current_word, "")[[1]])
    
    letter_number <- seq_along(letters)
    
    x2 <- coords$x2 - (letter_number-1) * ceiling(coords$pix_per_char)
    
    x1 <- coords$x2 - (letter_number) * ceiling(coords$pix_per_char)+1
    
    
    
    letter_coords <- tibble(letter = letters,
                            x1 = rev(x1),
                            x2 = rev(x2),
                            y1 = 0,
                            y2 = screen_height,
                            sent = 1,
                            line = 1)
      
    letter_coords[1,]$x1 <- coords$x1 + 1 # make sure that the beginning of the space is contiguous with the end of the last word
    
    letter_coords <- letter_coords %>% filter(x2 > x_offset) # remove the space if it would be to the left of the x offset (this will only happen for the first word of a sentence)  
    
    letter_coords$char_word <- seq_along(letter_coords$letter)
    
    letter_coords$space <- letter_coords$letter == " "
   
    return(letter_coords)
  }

 get_FIX_stamp <- function(string) {
  num_stamp <- NULL
  for (i in 1:length(string)) {
    char_stamp <-
      substr(string[i], 1, unlist(gregexpr(pattern = '\t', string[i]))[1] - 1)
    num_stamp[i] <- as.numeric(char_stamp)
  }
  # char_stamp<-substr(string, 1, unlist(gregexpr(pattern ='\t', string))[1]-1)
  # num_stamp <- as.numeric(char_stamp)
  return(num_stamp)
}

loc_blinks <-
  function(blink_time, s_time) {
    findInterval(blink_time, s_time) + 1
  }
# +1 because it affects the next fixation

get_x_pixel <- function(string) {
  a <- tibble(do.call(rbind, strsplit(string, '\t')))
  x <- as.numeric(as.character(unlist(a$X4)))
  
  return(x)
}

# in case of weird formatting (e.g., Cohen's script...)
get_x_pixel_ALT <- function(string) {
  a <- tibble(do.call(rbind, strsplit(string, ' ')))
  x <- a[a != ""][6]
  
  return(x)
}

get_y_pixel <- function(string) {
  a <- tibble(do.call(rbind, strsplit(string, '\t')))
  y <- as.numeric(as.character(unlist(a$X5)))
  
  return(y)
}

# in case of weird formatting (e.g., Cohen's script...)
get_y_pixel_ALT <- function(string) {
  a <- tibble(do.call(rbind, strsplit(string, ' ')))
  y <- a[a != ""][7]
  return(y)
}


get_seq <- function(start, end, file, prev = F) {
  if (!prev) {
    # find start:
    lines <- grep(start, file)
    hits <- file[lines]
    loc <- grep("SFIX", hits)
    s1 <- lines[loc] + 1
    
    # find end:
    lines2 <- grep(end, file)
    hits2 <- file[lines2]
    loc2 <- grep("EFIX", hits2)
    #hits2<- hits2[-loc2]
    s2 <- lines2
    s2 <- s2[-loc2]
    
    # extract fixation txt data:
    text <- file[s1:s2]
    out <-  as.tibble(do.call(rbind, strsplit(text, '\t')))
    out$V2 <- as.numeric(as.character(out$V2))
    out$V3 <- as.numeric(as.character(out$V3))
    out$V4 <- as.numeric(as.character(out$V4))
    
  } else{
    # find start:
    s1 <- grep(start, file)
    if (length(s1) > 1) {
      s1 <- s1[1]
    }
    
    
    # find end:
    s2 <- grep(end, file)
    if (length(s2) > 1) {
      s2 <- s2[1]
    }
    
    text <- file[s1:s2]
    
    whichSSACC <- which(grepl('SSACC', text))
    whichESACC <- which(grepl('ESACC', text))
    whichSFIX <- which(grepl('SFIX', text))
    whichEFIX <- which(grepl('EFIX', text))
    whichMSG <- which(grepl('MSG', text))
    whichSBLINK <- which(grepl('SBLINK', text))
    whichEBLINK <- which(grepl('EBLINK', text))
    
    allOut <-
      c(whichSSACC,
        whichESACC,
        whichSFIX,
        whichEFIX,
        whichMSG,
        whichSBLINK,
        whichEBLINK)
    
    if (length(allOut) > 0) {
      text <- text[-allOut]
    }
    
    out <-  as_tibble(do.call(rbind, strsplit(text, '\t')))
    out$V2 <- as.numeric(as.character(out$V2))
    out$V3 <- as.numeric(as.character(out$V3))
    out$V4 <- as.numeric(as.character(out$V4))
    
  }
  
  return(out)
  
}


process_trial <-
  function(file,
           trial_db,
           sub,
           tBlink = 50,
           textStim = NULL,
           ppl = NULL,
           xOffset = NULL,
           make_plot = FALSE) {
    
    cat(trial_db$item, "\n")
    raw_fix_temp <- NULL
    if (nrow(trial_db) > 1) {
      trial_db <- trial_db[1, ]
      warning(
        "The trial_db argument to the process_trial function should contain exactly one row, but a data frame with more than one row was passed. Only using the first row."
      )
    }
    
    xOffset <- trial_db$sentence_start_x
    
    ResY <- trial_db$height
    
    ResX <- trial_db$width
    
    text <-
      get_text(file[trial_db$ID:trial_db$start]) # get text details (Eyetrack)
    
    coords <-
          get_coord(text, x_offset = xOffset, screen_height = ResY)   # extract text coordinates

    map <-
      coord_map(coords, x = ResX, y = ResY, ignore_y = TRUE) # map them to pixels on the screen
    
    # Extract raw fixations from data and map them to the text:
    raw_fix_temp <-
          parse_fix(file, map, coords, trial_db, sub, ResX, ResY, tBlink, SL = TRUE)
  
    # remove eye movements made after trial was ended by participant looking in the bottom right corner
    # This removes eye movements during questions
    fix_max_x <- cummax(raw_fix_temp$xPos)
    fix_max_y <- cummax(raw_fix_temp$yPos)
    
    raw_fix_temp <- filter(raw_fix_temp, !(fix_max_x > .9*ResX & fix_max_y > .9*ResY))
    
    # make plots for testing
    if(make_plot){
    library(ggplot2)
    library(ggrepel)
    (ggplot(data = raw_fix_temp, aes(x = xPos, y = yPos, label = wordID)) +
    geom_rect(data = coords, aes(xmin = x1, xmax = x2, ymin = y1+500, ymax = y2-500, colour = space,  x = x1 + 5, y = y1 + 540, fill = char)) + geom_text(data = coords, colour = "white", aes(x = x1 + 5, y = y1 + 540, label = letter)) + scale_fill_viridis_c(end = .8) +
      geom_point(aes(size = fix_dur)) + geom_text(aes(label = fix_num, size = fix_dur), colour = "white") + geom_path(aes(colour = factor(regress))) + scale_y_reverse() + geom_text_repel(force = 3, colour = "orange") + geom_text_repel(colour = "red", force = 3, aes(label = round(fix_dur)))) %>%
      ggsave(filename = paste0("trial_plots/","THE_Subject_",sub,"_Trial_",trial_db$item,".pdf"), width = 19.2, height = 10.8)
    }
      
     return(raw_fix_temp)
  }

process_file <-
  function(current_filename,
           tBlink = 50,
           textStim = NULL,
           ppl = NULL,
           xOffset = NULL,
           make_plot = FALSE) {
    {
      sub_number <-
        gsub(x = current_filename,
             pattern = "[A-Za-z/_]*([0-9]*).[a-z]*",
             replacement = "\\1") %>% as.numeric
      
      current_file <- readLines(current_filename) # load file
      
      cat(current_file[1], "\n") # write first line of current file
      
      trial_db <-
        trial_info(
          current_file,
          maxtrial = 400,
          trial_flag = "TRIALID",
          trial_start_flag = "DISPLAY ON",
          parse_itemID = parse_itemID_ben_experiment
        )
      
      os_info <- get_OpenSesame_info(current_file) %>%
        filter(sentence_number < 900) # remove practice sentences
        
      trial_db <- left_join(trial_db,
                            os_info,
                            by = c("item" = "sentence_number"),
                            suffix = c("", ".os")
                          )
      
      cat("Processing trials...")
      raw_fix <- trial_db %>%
        split(.$item) %>%
        purrr::map(process_trial, file = current_file, sub = sub_number, tBlink = tBlink, make_plot = TRUE)
        #furrr::future_map(.f = process_trial, file = current_file, sub = sub_number, tBlink = tBlink, make_plot = TRUE, .progress = TRUE)
      
       raw_fix_bound <- bind_rows(raw_fix)
      
      cat("Done\n")
      sink(file = gsub(x = current_filename, pattern = "asc", "log")) # write a log file with the information from clean_data
      clean_data <- cleanData(raw_fix_bound, silent = FALSE)
      sink()
      fix_measures <- wordMeasures(clean_data)

      fix_measures_skip <- fix_measures %>%
        group_by(sub) %>% nest() %>%
        mutate(data = purrr::map(data, function(df) {
          right_join(df, corpus, by = c("item" = "item", "word" = "word"))
        })) %>%
        unnest(cols = c(data)) %>% left_join(trial_db,
                               by = c("item" = "item"),
                               suffix = c("", ".os")) %>%
        mutate(first_pass_skip = is.na(FFD))
      return(fix_measures_skip)

    }
    
  }

