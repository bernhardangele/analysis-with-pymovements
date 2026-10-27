use Fcntl;

print "\t\t\tTim8DROP program (2/23/10)\n\nThis program converts Eyelink ASC output files from the eyetrack0.7.**\n
program into a DA1 format that can be read by eyedry.\n";
print "Note that the program currently can only handle data from single line studies!!!\nCHECK BACK SOON for a version that is capable of handling mulitple lines.";
print "NOTE This program uses the UMASS style of condition and item numbers E##I##D##\n";

 print "Please provide output file extension (e.g., da1): ";
 $ext = <STDIN>; 
chomp ($ext);   

######################################################
#####       Start Parameter setup                #####
######################################################
##### This bit of code attempts to read in a     #####
##### bunch of parameters that I don't want to   #####
##### type in everytime that I ran the program   #####
#####       					 #####
#####  Things included:			         #####
#####	Eye being tracked (if more than 1)	 #####
#####   number of conditions	                 #####
#####   range of condition numbers               #####
#####   Correct response for each condition      #####
#####	Stimuli Resolution (X and Y)		 #####
#####   I guess there is a maximum of 400	 ##### 
#####		conditions    			 #####
######################################################
for ($q = 0; $q < 500; $q++)
	{
	$paramarray[$q] = 0;
	}


#####  Firstly, I check to see if there is a parameter file already made ##### 
print "Have you created a parameter file? (y or n) ";
$tempcr = <STDIN>; 
chomp ($tempcr);
	if ( ($tempcr eq "y")||($tempcr eq "Y"))
	{
	#####  If there is one, this reads in the name of the file and the data from the file #####
		print "Please provide the parameter file name: ";
 		$paraname = <STDIN>; 
		chomp ($paraname);   
		open (PARAMETERFILE, $paraname) or die "Can't open datafile: $!\n";
		$s = 0;
		while ($condline = <PARAMETERFILE>) 
		{
			chomp $condline;
			$paramarray[$s] = $condline;
			print "$paramarray[$s]\n";
			$s = $s +1; 

		}

	close PARAMETERFILE;
	}
	else 
	{
	##### If there is no parameter file, This will create the file #####
		print "Create new parameter file.\n";
		print "Please provide a parameter file name: ";
		$newparaname = <STDIN>; 
		chomp ($newparaname);   
		sysopen(NEWPARAMETERFILE, $newparaname, O_WRONLY|O_CREAT) or die "Can't open output file: $!\n";	
	
	##########################################################################
	##### The Picdry program only takes the data from one eye, so this   #####
	##### question asks which eye is to be analyzed.				     #####
	##### If there is only one eye recorded (which seems to be standard) #####
	##### the eye in the file is analyzed. If both eyes are there, this  #####
	##### will tell the program to pick either the R or L eye. 			 #####
	##########################################################################
	
	print "\nDoes the ASC file contain data from both eyes? y or n (Default = no) ";
	$eyenum = <STDIN>; 
	chomp ($eyenum);

	if ( $eyenum ne "y")
	{
		$paramarray[0] = "n";
		$paramarray[1] = "nada";
		# $eyenum = "n";
		# $whichI = "nada";
	}
	else
	{
		print "\nWhich eye do you want to analyze? r or l (default = r) ";
		$whicheye = <STDIN>; 
		chomp ($whicheye);
		# $eyenum = "y";
		$paramarray[0] = "y";
		if (($whicheye eq "l")||($whicheye eq "L"))
		{
		 # $whichI = "L";
		 $paramarray[1] = "L";
		}
		else 
		{
		   #   $whichI = "R";
		$paramarray[1] = "R";
		}
	}

        ########################################################################
	##### This section takes in the stimuli resolution because Eyelink #####
	##### records everything in the windows resolution of the display. #####
	##### This means that while the stimuli might be 800x600, Eyelink  #####
	##### might record its gaze coordinates (which are the data used)  #####
	##### in 1280x1024 or 1600x1200 pixels. In order to put the 	   #####
	##### fixations into the stimuli coordinates (which is how Picdry  #####
	##### operates) a correction/conversion is needed. Also, if people #####
	##### change the base resolution of the screen (like what	   #####
	##### happened to me), the current program will make the  	   #####
	##### appropriate correction back to the pixel coordinates of the  #####
	##### stimuli. 		      					   #####
	##### I still don't understand the logic of the Eyelink system 	   #####
	##### in this, but what can I do other than fix it. Alas.   	   #####
	########################################################################
	print "\nStimuli Screen Resolution X dimension (in pixels; e.g., 800) :";
		$screenx = <STDIN>; 
		chomp ($screenx);
		
		$paramarray[2] = $screenx;  ###### Size of X dimension of stimuli in pixels ##### 


	print "\nStimuli Screen Resolution Y dimension (in pixels; e.g., 600) :";
		$screeny = <STDIN>; 
		chomp ($screeny);
		
		$paramarray[3] = $screeny;  ###### Size of Y dimension of stimuli in pixels ##### 
		
		############################################################################################
		##### Picdry can use a accuracy variable which we don't get out of the Eyelink program #####
		##### Here is a way to get that data into the output. This is not elegant, but it does #####
		##### work. But it only works if the correct response is always the same for a         #####
		##### condition number. Currently, it matches the button pressed with the condition-   #####
		##### correct response to see if the response was accurate. If you can't think far     #####
		##### enough ahead to use different conditions for different responses then you won't  #####
		##### get what you want. Therefore, THINK AHEAD WHEN MAKING THE STIM FILES!!!!!!!!!!   #####
		#####					        		                       #####
		##### Buttons: Blue = 1, Red = 2, Green = 3, Yellow = 4, Purple = 5  	               #####
		############################################################################################		
		print "\nCorrect responses\n These will need to be consecutive condition numbers, \nbut can start at any number you want. \n\n";
		print "\n What is the low condition number? ";
		$condnumlow = <STDIN>; 
		chomp ($condnumlow);

		print "\nWhat is the high condition number? ";
		$condnumhigh = <STDIN>; 
		chomp ($condnumhigh);
	
		$high = $condnumhigh +1;
		
		print "\n";
		
		for ($w = $condnumlow; $w < $high; $w++)
		{	# This loop takes in the correct responses for each condition in the experiment
		print "Correct response for Condition $w? ";
		$condacctemp = <STDIN>; 
		chomp ($condacctemp);
		$paramarray[$w+3] = $condacctemp;
		}
	
	for ($p = 0; $p < ($condnumhigh+4); $p++)
	{ # Here we write out the parameter file
	print NEWPARAMETERFILE "$paramarray[$p]\n";
	}


	close NEWPARAMETERFILE;
	}
	
	##############################################
	#####	End of Parameter file writer	######
	##############################################


$eyenum = $paramarray[0];
$whichI = $paramarray[1];
$resx = $paramarray[2];#screen X coordinates 
$resy = $paramarray[3];#screen Y coordinates
#print "\n$eyenum    $whichI";

######################################################
#####      End of parameter reading              #####
######################################################
$ms_comb = 80; #this sets the short fixation duration for the purpose of counting such fixations. This value can be changed if the user wishes to combine short fixations.
print "Please provide a summary file name: ";
$summaryname = <STDIN>;
chomp ($summaryname);   
sysopen(SFILE, $summaryname, O_WRONLY|O_CREAT) or die "Can't open output file: $!\n";
print "This program has not been idiot proofed. Please be sure to input appropriate values when prompted and check your summary file when done.\n\n";

print "This program will create DA1 files with either a character or pixel location mapping.\nPlease note that eyedry requires a DA1 files with a character mapping.\n";
print "Do you want fixations mapped to characters (1) or pixels (2): ";
$charpix = <STDIN>;
chomp ($charpix);

if($charpix != 1 and $charpix != 2)
  {
    print "please enter either a 1 (character) or 2 (pixel) at the prompt: ";
    $charpix = <STDIN>;
    chomp ($charpix);
  }
if($charpix == 1)
  {
    print "Were the sentences presented as inline text (1) or prepared bitmaps (2)? ";
    $inline = <STDIN>;
    chomp ($inline);    
    print "Does the data come from a display change experiment (Y or N)? ";
    $dcexp = <STDIN>;
    chomp ($dcexp);
    print SFILE "Mapping fixations to characters.\n";
  }
elsif($charpix == 2)
  {
    print "Does the data come from a display change experiment (Y or N)? ";
    $dcexp = <STDIN>;
    chomp ($dcexp);
    print SFILE "Mapping fixations to pixels.\n";
  }
if($inline == 2)
  {
    print "What is the x offset (the left edge of the first character) in pixels? ";
    $xoffset = <STDIN>;
    chomp ($xoffset);
    print "How wide are the individual characters (only works for fixed width fonts) in pixels? ";
    $charwidth = <STDIN>;
    chomp ($charwidth);
    print SFILE "X offset = $xoffset.\nCharacter width set at $charwidth pixels.\n";
    for($cxp = $xoffset; $cxp < $resx; $cxp = $cxp + $charwidth)#THIS SETS THE PIXEL TO CHAR MAPPING FOR BITMAP TEXT
      {
	push (@pixx, $cxp);
	#print "$pixx[0]\t$pixx[1]\n";
      }
  }
if(($dcexp eq "Y")||($dcexp eq "y"))
  {
    print "Do you want the fixations mapped to the preview characters (1) or the target characters (2)? ";
    $disptext = <STDIN>;
    chomp ($disptext);
    if($dispext == 1)
      {
	print SFILE "Mapping fixations to preview characters.\n";
      }
    else
      {
	print SFILE "Mapping fixations to target characters.\n";
      }
  }else
  {
    $disptext = 1;
  }

print "Do you want to combine short fixations that are close to each other (Y or N)? ";
$combine = <STDIN>;
chomp ($combine);
	
if ( ($combine eq "y")||($combine eq "Y"))
  {
    print "How close do the fixations need to be in pixels for combining? ";
    $pix_comb = <STDIN>;
    chomp ($pix_comb);
    print "How short does a fixation need to be in milliseconds for combining? ";
    $ms_comb = <STDIN>;
    chomp ($ms_comb);
    print SFILE "Combining temporally adjacent fixations that are within $pix_comb pixels of each other if at least one of them is below $ms_comb ms.\n";
  }

print "Do you have an eyedry count file and want to exclude trials due to blinks or long fixations on a target region(Y or N)? ";
$blinklong = <STDIN>;
chomp ($blinklong);
	
if ( ($blinklong eq "y")||($blinklong eq "Y"))
  {
    while (($rightreg ne "y") and ($rightreg ne "Y"))
      {
    print "Please enter the name of the eyedry count file ";
    $cntname = <STDIN>;
    chomp ($cntname);
    open (CNTFILE, $cntname) or die "Can't open countfile: $!\n";
    print "Will you be using 1 or 2 critical regions? ";
    $numcritreg = <STDIN>;
    chomp ($numcritreg);
    if($numcritreg == 1)
      {
	print "Which region is the critical region? ";
	$critregion1 = <STDIN>;
	chomp ($critregion1);
	print "Getting the critical regions! Please stay tuned.\nYou will want to check these to make sure the right region is specified for each item and condition combination\n"; 
      }
    if($numcritreg == 2)
      {
	print "Which is the first region? ";
	$critregion1 = <STDIN>;
	chomp ($critregion1);
	print "Which is the second region? ";
	$critregion2 = <STDIN>;
	chomp ($critregion2);
	print "Getting the critical regions! Please stay tuned.\nYou will want to check these to make sure the right region is specified for each item and condition combination\n"; 
      }
    while ($regline = <CNTFILE>)
      {
	chomp ($regline);
	@regdata = split (/\s\s*/, $regline); #This splits the line by tabs or spaces treating mulitple tabs or spaces as a single delimiter
	if (( $regdata[3] < $critregion1 ) or ($regdata[3] < $critregion2))
	  {
	    print "There are only $regdata[3] regions in your file so the critical region you entered does not exist.\n";
	    print "Please enter a critical region less than or equal to $regdata[3] to continue ";
	    $critregion = <STDIN>;
	    chomp ($critregion);
	  }
	else
	  {
	    $critstart1 = $regdata[$critregion1 + 3];
	    $critend1 = $regdata[$critregion1 + 4];
	    push (@itemregion, $regdata[1], $regdata[2], $critstart1, $critend1);
	    print "\n$regdata[1]\t$regdata[2]\t$critstart1\t$critend1";
	    if($numcritreg == 2)
	      {
		$critstart2 = $regdata[$critregion2 + 3];
		$critend2 = $regdata[$critregion2 + 4];
		push (@itemregion, $critstart2, $critend2);
		print "\t$critstart2\t$critend2";
	      }
	    else
	      {
		$critstart2 = -2;
		$critend2 = -2;
		push (@itemregion, $critstart2, $critend2);
		print "\t$critstart2\t$critend2";
	      }
	  }
      }
    print "\nAre these the correct regions (Y or N)? ";
    $rightreg = <STDIN>;
    chomp ($rightreg);
    if (($rightreg eq "y")||($rightreg eq "Y"))
      {
	print "Good, let's continue!\n"
      }
    else
      {
	print "OK let's try that again\n";
      }
  }
    print "Do you want to exclude based on first pass reading only (1) or on all reading (2) or Go-past only (3)? ";
    $FPonly = <STDIN>;
    chomp ($FPonly);
    print "What is the longest valid fixation time to include on the critical region(s)? ";
    $longcut = <STDIN>;
    chomp($longcut);
    print "Changing condition number of trials with blinks on or near the critical region to 99\n";
    print SFILE "Changing condition number of trials with blinks on or near the critical region to 99.\nHere near refers to the fixation immediately prior to or immediately following a fixation on the critical region\n";
    print "Changing condition number of trials with fixations over $longcut on or near the critical region to 98.\n";
    print SFILE "Changing condition number of trials with fixations over $longcut on or near the critical region to 98.\nHere near refers to the fixation immediately prior to or immediately following a fixation on the critical region\n";
  }
print "Please provide the data list file: ";
$lstname = <STDIN>; 
chomp ($lstname);   

open (LISTFILE, $lstname) or die "Can't open listfile: $!\n";
#gets the list file in from the user which contains the names of the files that will be run
$expshort = 0;
$explong = 0;
$expcomb = 0;
$expblink = 0;
$expfixnum = 0;
$expblinkbad = 0;
$explongbad = 0;

while ($filename = <LISTFILE>)
  {
    chomp ($filename);
    open (INDATA, $filename) or die "Can't open datafile: $!\n";
    substr($filename, -3, 3) = $ext;#in a rather ugly way, I change the file extension for output
    unlink($filename); # this erases output prior to adding input to prevent garbage from being left around
    sysopen(FH, $filename, O_WRONLY|O_CREAT) or die "Can't open output file: $!\n";
    # sysopen(FH, $name, O_WRONLY|O_EXCL|O_CREAT) or die "Can't open output file: $!\n";
    # this one will not run if the file exists : O_EXCL means fail if exists
    print "Output file name:\t$filename\n";
    print SFILE "Output file name:\t$filename\n";
	######################################################
	#####        End of File Setup                   #####
	######################################################
	######################################################
	#####        Begin file reading                  #####
	######################################################
    $trialnum = 0;
    $displayon = 0;
    $fixcount = 0;
    $subshort = 0;
    $sublong = 0;
    $subcomb = 0;
    $subblink = 0;
    $subfixnum = 0;
    $subblinkbad = 0;
    $sublongbad = 0;
    while ($line = <INDATA>) 
      {
	@dataline = split(" ", $line); # this splits the line up using space as the delimiter
	$numel = @dataline; # gets the total number of elements on the line -- I don't know if this is needed or not
	if ($dataline[0] eq "MSG")
	  {
	   if ($dataline[2] eq "TRIALID") # this finds the beginning of a trial
	     {
	       $conditem = $dataline[3]; # this is the condition/item identifier
	       @conditionitem = split(/I/,$conditem);
	       @itemcatch = split(/D/,$conditionitem[1]);
	       $item = $itemcatch[0];
	       $cond = $conditionitem[0];
	       $itemtype = substr($cond, 0, 1);
	       substr($cond, 0, 1) = " ";       # delete first character
	       $displayon = 0;
	       $trialokflag = 0;
	       $done = 0;
	       $startcrit1 = -2;
		   $endcrit1 = -2;
		   $startcrit2 = -2;
		   $endcrit2 = -2;
	       $FP1tritog = 0;
	       $FP2tritog = 0;
	       if ($itemtype eq "E")
		 {
		   for($findreg = 0; $findreg < ($#itemregion - 4); $findreg = $findreg + 6)
		     {
		       if (($itemregion[$findreg] == $item) and ($itemregion[$findreg + 1] == $cond))
			 {
			   $startcrit1 = $itemregion[($findreg + 2)];
			   $endcrit1 = $itemregion[($findreg + 3)];
			   $startcrit2 = $itemregion[($findreg + 4)];
			   $endcrit2 = $itemregion[($findreg + 5)];
			   $findreg = $#itemregion;
			   print "found region\t$item\t$cond\t$startcrit\t$endcrit\n";
			 }
		     }
		   if ( ($blinklong eq "y")||($blinklong eq "Y"))
		     {
		       if ($startcrit1 == -2)
			 {
			   print "WARNING item $item condition $cond never found critical region\n";
			   print SFILE "WARNING item $item condition $cond never found critical region\n";
			 }
		     }
		 }
		   if($inline != 2)
		     {
		       @charx = ("");
		       @chary = ("");
		       @pixx = ("");
		       @pixy = ("");
		       @char = ("");
		     }
	     }
	   if(($dataline[2] eq "DISPLAY") && ($dataline[3] eq "TEXT"))
	     {
	       if($dataline[4] == $disptext)
		{
		  $getcharpix = 1; #toggle variable used to turn on and off the loop that pushes the character and pixel locations into arrays for comparison
		}else
		{
		  $getcharpix = 2;
		}
	     }
	   if(($getcharpix == 1) and ($inline != 2))
	     {
	       if ($dataline[2] eq "REGION")
		 {
		   push (@charx, $dataline[4]);
		   push (@chary, $dataline[5]);
		   if($#dataline == 10)
		     {
		       push (@char, $dataline[6]);
		       push (@pixx, $dataline[7]);
		       push (@pixy, $dataline[8]);
		     }elsif($#dataline == 9)
		       {
			 push (@char, " ");
			 push (@pixx, $dataline[6]);
			 push (@pixy, $dataline[7]);
		       }
		 }
	     }
	   if(($dataline[2] eq "TRIAL") && ($dataline[3] eq "OK"))
	     {
	       $trialokflag = 1;
	     }		
  	   if(($dataline[2] eq "DISPLAY") && ($dataline[3] eq "ON")) 
	     {
	       $trialstarttime = $dataline[1];
	       $displayon = 1;
	       $getcharpix = 2;
	       @initfixlistC = ("");
	       @initfixlistP = ("");
	       @finfixlistC = ("");
	       @finfixlistP = ("");
	       @blinker = ("");
	       $fixcount = 0;
	       $shortcount = 0;
	       $num_comb = 0;
	       $numblink = 0;
	     }
  	   if ($dataline[2] eq "GAZE_COORDS") 
	     {
	       $screenresX = $resx/($dataline[5]+1);
	       $screenresY = $resy/($dataline[6]+1);
	       # This if statement constantly checks the coordinates that the eyelink is recording in and compares it to the 
	       # stimuli dimensions. What I get out of this is a multiplier that can be used to convert Eyelink coordinates into
	       # pixel coordinates of the actual stimuli.By checking every trial, we insure that nothing funky is happening
	     }
	   if ($dataline[2] eq "ENDBUTTON") #&& ($displayon == 1))
	     {
	       $trialendtime = $dataline[1];
	       $rt = $trialendtime - $trialstarttime;
	       $resp = $dataline[3];
	       $done = 2;
	       if ($resp == $paramarray[$cond + 3]) 
		 {
		   $respacc=1;
		 }
	       else
		 {
		   $respacc = 0;
		 }
	     }
	 }
	if ($dataline[0] eq "SBLINK")
	     {
		$blink = 1;
	     }
	if (($dataline[0] eq "EFIX") && ($displayon == 1))
	  {
	    if (($eyenum eq "n") || ($dataline[1] eq $whichI))
	      { # allows only those fixations that come from only one eye
		# Here are all of the fixation information bits:
		$fixstart = $dataline[2];
		if($fixstart < $trialstarttime)
		  {
		    $fixstart = $trialstarttime;#this removes the time that the gaze box was on from the first fixations not sure we want to do this
		  }
		if(($fixcount == 0) and ($fixstart > $trialstarttime)) #This makes the first fixation start at 0 ms when there was a saccade or blink when at DISPLAY ON
		  {
		    $trialstarttime = $fixstart;
		  }
		$fixend = $dataline[3];
		$fixduration = $dataline[4];
		$fix_xpos = sprintf("%.0f", ($dataline[5] * $screenresX));# This is a correction for the screen resolution 
		$fix_ypos = sprintf("%.0f", ($dataline[6] * $screenresY)); # This is a correction for the screen resolution
		$fix_ychar = 0;
		for ($character = 1; $character <= $#pixx; $character ++)
		  {
		    #print "$pixx[$character]\n";
		    if(($fix_xpos < $pixx[1]) or ($fix_xpos > ($pixx[$#pixx] + 11)))
		      {#this is a cludge to make sure that fixations to the left of the first letter or to the right of the last letter don't mess up the works.
			$fix_xchar = -1;
			$fix_ychar = -1;
		      }
		    elsif(($fix_xpos >= $pixx[$character]) and ($fix_xpos < $pixx[$character + 1]))
		      {
			$fix_xchar = ($character - 1);
			$character = $#pixx+1;
		      }
		  }
		$fixcount = $fixcount + 1;	
		#print "$dataline[2]\t$dataline[3]\t$dataline[4]\t$dataline[5]\t$dataline[6]\t";
		#print FH "$fixstart\t$fixend\t$fixduration\t$fix_xpos\t$fix_ypos\t";
		push (@initfixlistC, $fix_xchar, $fix_ychar, ($fixstart - $trialstarttime), ($fixend - $trialstarttime) ); # this line puts in X Y Start Stop into the array
		push (@initfixlistP, $fix_xpos, $fix_ypos, ($fixstart - $trialstarttime), ($fixend - $trialstarttime) );# this line puts in X Y Start Stop into the array
		push (@blinker, $blink);#this array codes whether or not a blink occurred since the last EFIX
		$blink = 0;
	      }
	  }
	if(($itemtype eq "E") and ($done == 2))
	  {
	    $done = 1;
	    if ( ($combine eq "y")||($combine eq "Y")) #this is the loop that handles the combining of short fixations
	      {#combining loop entered
		for($init2fin = 1; $init2fin < $#initfixlistP; $init2fin = $init2fin + 4) #loops through the fixations
		  {
		    $currentfix = ($init2fin + 3)/4;#this calculates what fixation number the loop is working on which can be used by the blinker array
		    #print "$init2fin\t$#initfixlistP\t$itemtype\t$#initfixlistC\t$ms_comb\t$pix_comb\t$initfixlistP[$init2fin + 3]\t$initfixlistP[$init2fin + 2]\n";
		    
		    if(($initfixlistP[$init2fin + 3] - $initfixlistP[$init2fin + 2]) > $longcut) #determines if the current fixation is over the limit
		      {
			$sublong = $sublong + 1;
			$explong = $explong + 1;
		      }
		    if(($initfixlistP[$init2fin + 3] - $initfixlistP[$init2fin + 2]) < $ms_comb) #determines if the current fixation is under the limit
		      {
			if($blinker[$currentfix] == 0)
			  {
			    $shortcount = $shortcount + 1;
			    $prenear = abs($initfixlistP[$init2fin] - $initfixlistP[$init2fin - 4]); #determines the absolute distance of the current fixation from the previous
			    $postnear = abs($initfixlistP[$init2fin] - $initfixlistP[$init2fin + 4]); #determines the absolute distance of the current fixation from the following
			    if(($prenear <= $postnear) and ($prenear <= $pix_comb)) #determines if the previous fixation is the closest and if it is close enough
			      {
				if($blinker[($currentfix - 1)] == 0) #determines if the previous fixation is free from blinks
				  {
				    print "$filename\tcondition: $cond\t item: $item\tcombining fixation $currentfix with previous fixation\n";
				    print SFILE "$filename\tcondition: $cond\t item: $item\tcombining fixation $currentfix with previous fixation\n";
				    pop (@finfixlistP); #removes the last element from the final fixation array which is the endtime of the previous fixation
				    push (@finfixlistP, $initfixlistP[$init2fin + 3]); #adds the endtime of the current fixation to the end of the array (this adds saccade time too)
				    pop (@finfixlistC);
				    push (@finfixlistC, $initfixlistC[$init2fin + 3]);
				    splice (@blinker, $currentfix, 1);
				    $num_comb = $num_comb + 1;
				  }
			      }
			    elsif(($prenear > $postnear) and ($postnear <= $pix_comb)) #determines if the following fixation is the closest and if it is close enough
			      {
				if($blinker[($currentfix + 1)] == 0) #this makes sure that the folowing fixation is blink free for combining
				  {
				    if(($initfixlistP[$init2fin + 7] - $initfixlistP[$init2fin + 2]) >= $ms_comb) #determines if the combining will result in a fixation over the cutoff
				      {
					print "$filename\tcondition: $cond\t item: $item\tcombining fixation $currentfix with next fixation\n";
					print SFILE "$filename\tcondition: $cond\t item: $item\tcombining fixation $currentfix with next fixation\n";
					push (@finfixlistP, $initfixlistP[$init2fin + 4], $initfixlistP[$init2fin + 5], $initfixlistP[$init2fin + 2], $initfixlistP[$init2fin + 7]); 
					push (@finfixlistC, $initfixlistC[$init2fin + 4], $initfixlistC[$init2fin + 5], $initfixlistC[$init2fin + 2], $initfixlistC[$init2fin + 7]);
					splice (@blinker, $currentfix, 1);
					#adds the next fixation to the final array except using the current fixations startime--adds saccade time too 
					$init2fin = $init2fin + 4; #moves past the next fixation since this has already been incorporated into the final array
					$num_comb = $num_comb + 1;
				      }
				    else #when the combining of the current and next fixation results in a fixation that is too short
				      {
					print "warning!! possible short fixation issues with $filename item: $item\n";
					print SFILE "warning!! possible short fixation issues with $filename item: $item\n";
					if(abs($initfixlistP[$init2fin + 4] - $initfixlistP[$init2fin + 8]) <= $pix_comb)
					  {
					    print "$filename\tcondition: $cond\t item: $item\tcombining fixation $currentfix with fixation N+2\n";
					    print SFILE "$filename\tcondition: $cond\t item: $item\tcombining fixation $currentfix with fixation N+2\n";
					    push (@finfixlistP, $initfixlistP[$init2fin + 4], $initfixlistP[$init2fin + 5], $initfixlistP[$init2fin + 2], $initfixlistP[$init2fin + 11]);
					    push (@finfixlistC, $initfixlistC[$init2fin + 4], $initfixlistC[$init2fin + 5], $initfixlistC[$init2fin + 2], $initfixlistC[$init2fin + 11]);
					    #adds the N+2 fixation to the final array except using the current fixations startime--adds saccade times too
					    splice (@blinker, $currentfix, 2);
					    $init2fin = $init2fin + 8; #moves past the next two fixations since they have already been incorporated into the final array
					    $num_comb = $num_comb + 1;
					  }
					else
					  {
					    print "$filename\tcondition: $cond\t item: $item\tcombining fixation $currentfix with previous fixation2\n";
					    print SFILE "$filename\tcondition: $cond\t item: $item\tcombining fixation $currentfix with previous fixation2\n";
					    push (@finfixlistP, $initfixlistP[$init2fin + 4], $initfixlistP[$init2fin + 5], $initfixlistP[$init2fin + 2], $initfixlistP[$init2fin + 7]);
					    push (@finfixlistC, $initfixlistC[$init2fin + 4], $initfixlistC[$init2fin + 5], $initfixlistC[$init2fin + 2], $initfixlistC[$init2fin + 7]);
					    splice (@blinker, $currentfix, 1);
					    #adds the next fixation to the final array except using the current fixations startime--adds saccade time too 
					    $init2fin = $init2fin + 4; #moves past the next fixation since this has already been incorporated into the final array
					    $num_comb = $num_comb + 1;
					  }
				      }   
				  }
				else #pushes the bad fixations onto the array so there aren't gaps
				  {
				    push (@finfixlistP, $initfixlistP[$init2fin], $initfixlistP[$init2fin + 1], $initfixlistP[$init2fin + 2], $initfixlistP[$init2fin + 3]);
				    push (@finfixlistC, $initfixlistC[$init2fin], $initfixlistC[$init2fin + 1], $initfixlistC[$init2fin + 2], $initfixlistC[$init2fin + 3]);
				  }
			      }
			    else
			      {
				push (@finfixlistP, $initfixlistP[$init2fin], $initfixlistP[$init2fin + 1], $initfixlistP[$init2fin + 2], $initfixlistP[$init2fin + 3]);
				push (@finfixlistC, $initfixlistC[$init2fin], $initfixlistC[$init2fin + 1], $initfixlistC[$init2fin + 2], $initfixlistC[$init2fin + 3]);
			      }
			  }
			else #pushes the bad fixations onto the array so they aren't gaps
			  {
			    push (@finfixlistP, $initfixlistP[$init2fin], $initfixlistP[$init2fin + 1], $initfixlistP[$init2fin + 2], $initfixlistP[$init2fin + 3]);
			    push (@finfixlistC, $initfixlistC[$init2fin], $initfixlistC[$init2fin + 1], $initfixlistC[$init2fin + 2], $initfixlistC[$init2fin + 3]);
			  }
		      }
		    else
		      {
			#print "good fix\n";
			push (@finfixlistP, $initfixlistP[$init2fin], $initfixlistP[$init2fin + 1], $initfixlistP[$init2fin + 2], $initfixlistP[$init2fin + 3]);
			push (@finfixlistC, $initfixlistC[$init2fin], $initfixlistC[$init2fin + 1], $initfixlistC[$init2fin + 2], $initfixlistC[$init2fin + 3]);
		      }
		  }#this ends the for loop that cycles through the fixation list
	      }#this ends the combining if statement
	    else
	      {
		@finfixlistP = @initfixlistP;
		@finfixlistC = @initfixlistC;
	      }#this else loop gets the final fixation lists for the case when the user doesn't want to combine fixations
	    if (($blinklong eq "y")||($blinklong eq "Y"))#this is the section where we look to exclude trials based on blinks or long fixations on or near the target
	      {
		if($FPonly == 1)
		  {
		    for($fin4exclude = 1; $fin4exclude < $#finfixlistP; $fin4exclude = $fin4exclude + 4) #loops through the fixations
		      {
			$fixcheck = ($#finfixlistP/4);
			
			if($finfixlistC[$fin4exclude] > $endcrit1) #determines if first pass for the first region is over
			  {
			    $FP1tritog = 2;
			  }
			if($finfixlistC[$fin4exclude] > $endcrit2) #determines if first pass for the second region is over
			  {
			    $FP2tritog = 2;
			  }
			if(($finfixlistC[$fin4exclude] < $startcrit1) and ($FP1tritog == 1))#determines if first pass for the first region is over
			  {
			    $FP1tritog = 2;
			  }
			if(($finfixlistC[$fin4exclude] < $startcrit2) and ($FP2tritog == 1))#determines if first pass for the second region is over
			  {
			    $FP2tritog = 2;
			  }
			if(($FP1tritog == 2) and ($FP2tritog == 2)) #exits the for loop if first pass for both targets has ended
			  {
			    $fin4exclude = $#finfixlistP;
			  }
			$currentfix2 = ($fin4exclude + 3)/4;#this calculates what fixation number the loop is working on which can be used by the blinker array
			print SFILE "$item\t$cond\t$#blinker\t$fixcheck\t$fin4exclude\t$currentfix2\t$blinker[$currentfix2]\t$finfixlistC[$fin4exclude]\n";
			if(($finfixlistC[$fin4exclude] >= $startcrit1) and ($finfixlistC[$fin4exclude] < $endcrit1))#this determines if the fixation is on the critical region
			  {
			    if($FP1tritog == 0)
			      {
				$FP1tritog = 1;
			      }
			    print "item $item condition $cond fixation $currentfix is on target between $startcrit1 and $endcrit1\n";
			    if(($blinker[$currentfix2] == 1) and ($FP1tritog == 1))#checks to see if the fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif(($blinker[$currentfix2 - 1] == 1) and ($FP1tritog == 1))#checks to see if the previous fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink immediately prior to a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink immediately prior to a fixation on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif(($blinker[$currentfix2 + 1] == 1) and ($FP1tritog == 1))#checks to see if the next fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink immediately following a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink immediately following a fixation on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif((($finfixlistP[$fin4exclude + 3] - $finfixlistP[$fin4exclude + 2]) > $longcut) and ($FP1tritog == 1))#checks to see if the fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif((($finfixlistP[$fin4exclude - 1] - $finfixlistP[$fin4exclude - 2]) > $longcut) and ($FP1tritog == 1))#checks to see if the previous fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation immediately prior to a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation immediately prior to a fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif((($finfixlistP[$fin4exclude + 7] - $finfixlistP[$fin4exclude + 6]) > $longcut) and ($FP1tritog == 1))#checks to see if the next fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation immediately following a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation immediately following a fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			  }
			if(($finfixlistC[$fin4exclude] >= $startcrit2) and ($finfixlistC[$fin4exclude] < $endcrit2))#this determines if the fixation is on the second critical region
			  {
			    if($FP2tritog == 0)
			      {
				$FP2tritog = 1;
			      }
			    print "item $item condition $cond fixation $currentfix is on target between $startcrit2 and $endcrit2\n";
			    if(($blinker[$currentfix2] == 1) and ($FP2tritog == 1))#checks to see if the fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif(($blinker[$currentfix2 - 1] == 1) and ($FP2tritog == 1))#checks to see if the previous fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink immediately prior to a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink immediately prior to a fixation on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif(($blinker[$currentfix2 + 1] == 1) and ($FP2tritog == 1))#checks to see if the next fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink immediately following a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink immediately following a fixation on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif((($finfixlistP[$fin4exclude + 3] - $finfixlistP[$fin4exclude + 2]) > $longcut) and ($FP2tritog == 1))#checks to see if the fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif((($finfixlistP[$fin4exclude - 1] - $finfixlistP[$fin4exclude - 2]) > $longcut) and ($FP2tritog == 1))#checks to see if the previous fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation immediately prior to a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation immediately prior to a fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif((($finfixlistP[$fin4exclude + 7] - $finfixlistP[$fin4exclude + 6]) > $longcut) and ($FP2tritog == 1))#checks to see if the next fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation immediately following a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation immediately following a fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			  }
		      }
		  }
		if($FPonly == 2)
		  {
		    for($fin4exclude = 1; $fin4exclude < $#finfixlistP; $fin4exclude = $fin4exclude + 4) #loops through the fixations
		      {
			$fixcheck = ($#finfixlistP/4);
			$currentfix2 = ($fin4exclude + 3)/4;#this calculates what fixation number the loop is working on which can be used by the blinker array
			print SFILE "$item\t$cond\t$#blinker\t$fixcheck\t$fin4exclude\t$currentfix2\t$blinker[$currentfix2]\t$finfixlistC[$fin4exclude]\n";
			if(($finfixlistC[$fin4exclude] >= $startcrit1) and ($finfixlistC[$fin4exclude] < $endcrit1))#this determines if the fixation is on the critical region
			  {
			    print SFILE "item $item condition $cond fixation $currentfix2 is on target between $startcrit1 and $endcrit1\n";
			    if($blinker[$currentfix2] == 1)#checks to see if the fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif($blinker[$currentfix2 - 1] == 1)#checks to see if the previous fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink immediately prior to a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink immediately prior to a fixation on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif($blinker[$currentfix2 + 1] == 1)#checks to see if the next fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink immediately following a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink immediately following a fixation on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif(($finfixlistP[$fin4exclude + 3] - $finfixlistP[$fin4exclude + 2]) > $longcut)#checks to see if the fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif(($finfixlistP[$fin4exclude - 1] - $finfixlistP[$fin4exclude - 2]) > $longcut)#checks to see if the previous fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation immediately prior to a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation immediately prior to a fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif(($finfixlistP[$fin4exclude + 7] - $finfixlistP[$fin4exclude + 6]) > $longcut)#checks to see if the next fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation immediately following a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation immediately following a fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			  }
			if(($finfixlistC[$fin4exclude] >= $startcrit2) and ($finfixlistC[$fin4exclude] < $endcrit2))#this determines if the fixation is on the critical region
			  {
			    print "item $item condition $cond fixation $currentfix is on target between $startcrit2 and $endcrit2\n";
			    if($blinker[$currentfix2] == 1)#checks to see if the fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif($blinker[$currentfix2 - 1] == 1)#checks to see if the previous fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink immediately prior to a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink immediately prior to a fixation on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif($blinker[$currentfix2 + 1] == 1)#checks to see if the next fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink immediately following a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink immediately following a fixation on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif(($finfixlistP[$fin4exclude + 3] - $finfixlistP[$fin4exclude + 2]) > $longcut)#checks to see if the fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif(($finfixlistP[$fin4exclude - 1] - $finfixlistP[$fin4exclude - 2]) > $longcut)#checks to see if the previous fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation immediately prior to a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation immediately prior to a fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif(($finfixlistP[$fin4exclude + 7] - $finfixlistP[$fin4exclude + 6]) > $longcut)#checks to see if the next fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation immediately following a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation immediately following a fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			  }
		      }
		  }
		  if($FPonly == 3)
		  {
		    for($fin4exclude = 1; $fin4exclude < $#finfixlistP; $fin4exclude = $fin4exclude + 4) #loops through the fixations
		      {
			$fixcheck = ($#finfixlistP/4);
			
			if($finfixlistC[$fin4exclude] > $endcrit1) #determines if first pass for the first region is over
			  {
			    $FP1tritog = 2;
			  }
			if($finfixlistC[$fin4exclude] > $endcrit2) #determines if first pass for the second region is over
			  {
			    $FP2tritog = 2;
			  }
			if(($FP1tritog == 2) and ($FP2tritog == 2)) #exits the for loop if first pass for both targets has ended
			  {
			    $fin4exclude = $#finfixlistP;
			  }
			$currentfix2 = ($fin4exclude + 3)/4;#this calculates what fixation number the loop is working on which can be used by the blinker array
			print SFILE "$item\t$cond\t$#blinker\t$fixcheck\t$fin4exclude\t$currentfix2\t$blinker[$currentfix2]\t$finfixlistC[$fin4exclude]\n";
			if(($finfixlistC[$fin4exclude] >= $startcrit1) and ($finfixlistC[$fin4exclude] < $endcrit1))#this determines if the fixation is on the critical region
			  {
			    if($FP1tritog == 0)
			      {
				$FP1tritog = 1;
			      }
			    print "item $item condition $cond fixation $currentfix is on target between $startcrit1 and $endcrit1\n";
			    if(($blinker[$currentfix2] == 1) and ($FP1tritog == 1))#checks to see if the fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif(($blinker[$currentfix2 - 1] == 1) and ($FP1tritog == 1))#checks to see if the previous fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink immediately prior to a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink immediately prior to a fixation on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif(($blinker[$currentfix2 + 1] == 1) and ($FP1tritog == 1))#checks to see if the next fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink immediately following a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink immediately following a fixation on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif((($finfixlistP[$fin4exclude + 3] - $finfixlistP[$fin4exclude + 2]) > $longcut) and ($FP1tritog == 1))#checks to see if the fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif((($finfixlistP[$fin4exclude - 1] - $finfixlistP[$fin4exclude - 2]) > $longcut) and ($FP1tritog == 1))#checks to see if the previous fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation immediately prior to a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation immediately prior to a fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif((($finfixlistP[$fin4exclude + 7] - $finfixlistP[$fin4exclude + 6]) > $longcut) and ($FP1tritog == 1))#checks to see if the next fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation immediately following a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation immediately following a fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			  }
			if(($finfixlistC[$fin4exclude] >= $startcrit2) and ($finfixlistC[$fin4exclude] < $endcrit2))#this determines if the fixation is on the second critical region
			  {
			    if($FP2tritog == 0)
			      {
				$FP2tritog = 1;
			      }
			    print "item $item condition $cond fixation $currentfix is on target between $startcrit2 and $endcrit2\n";
			    if(($blinker[$currentfix2] == 1) and ($FP2tritog == 1))#checks to see if the fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif(($blinker[$currentfix2 - 1] == 1) and ($FP2tritog == 1))#checks to see if the previous fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink immediately prior to a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink immediately prior to a fixation on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif(($blinker[$currentfix2 + 1] == 1) and ($FP2tritog == 1))#checks to see if the next fixation had a blink
			      {
				print "Changing condition number of item $item condition $cond for $filename * blink immediately following a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * blink immediately following a fixation on critical region fixation number $currentfix2\n";
				$cond = 99;
				$subblinkbad = $subblinkbad + 1;
				$expblinkbad = $expblinkbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif((($finfixlistP[$fin4exclude + 3] - $finfixlistP[$fin4exclude + 2]) > $longcut) and ($FP2tritog == 1))#checks to see if the fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif((($finfixlistP[$fin4exclude - 1] - $finfixlistP[$fin4exclude - 2]) > $longcut) and ($FP2tritog == 1))#checks to see if the previous fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation immediately prior to a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation immediately prior to a fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			    elsif((($finfixlistP[$fin4exclude + 7] - $finfixlistP[$fin4exclude + 6]) > $longcut) and ($FP2tritog == 1))#checks to see if the next fixation is too long
			      {
				print "Changing condition number of item $item condition $cond for $filename * long fixation immediately following a fixation on critical region fixation number $currentfix2\n";
				print SFILE "Changing condition number of item $item condition $cond for $filename * long fixation immediately following a fixation on critical region fixation number $currentfix2\n";
				$cond = 98;
				$sublongbad = $sublongbad + 1;
				$explongbad = $explongbad + 1;
				$fin4exclude = $#finfixlistP;
			      }
			  }
		      }
		  }
		  
	      }#this ends the if statement of itemtype and done
		  
	  }
	if (($trialokflag == 1) and ($done >= 1))
	  {
	    $a = $#finfixlistC;
	    if (@finfixlistC[$a] > $trialendtime)
	      {
		@finfixlistC[$a] = $trialendtime;
	      } # fixes a problem with the fixation time of last fixation by truncating to the endtime derived from the endbutton response
	    if (@finfixlistP[$a] > $trialendtime)
	      {
		@finfixlistP[$a] = $trialendtime;
	      } # fixes a problem with the fixation time of last fixation by truncating to the endtime derived from the endbutton response
	    if(($charpix == 1) and ($itemtype eq "E"))
	      {
		$newfixcount = $fixcount - $num_comb;
		$subfixnum = $subfixnum + $fixcount;
		$subshort = $subshort + $shortcount;
		$subcomb = $subcomb + $num_comb;
		$expfixnum = $expfixnum + $fixcount;
		$expshort = $expshort + $shortcount;
		$expcomb = $expcomb + $num_comb;
		for($cycle = 0; $cycle < $#blinker; $cycle++)
		  {		  
		    $numblink = $numblink + $blinker[$cycle];
		  }
		$subblink = $subblink + $numblink;
		$expblink = $expblink + $numblink;
		print FH "$trialnum\t $cond\t $item\t $numblink  \t $shortcount\t $num_comb\t $fixcount\t $newfixcount\t"; #fixlister[3] is the start time
		for ($i = 1; $i <= $a; $i++)
		  {
		    print FH "$finfixlistC[$i]\t";
		  }
		print FH "\n"; 
	      }
	    if(($charpix == 2) and ($itemtype eq "E"))
	      {
		$newfixcount = $fixcount - $num_comb;
		$subfixnum = $subfixnum + $fixcount;
		$subshort = $subshort + $shortcount;
		$subcomb = $subcomb + $num_comb;
		$expfixnum = $expfixnum + $fixcount;
		$expshort = $expshort + $shortcount;
		$expcomb = $expcomb + $num_comb;
		for($cycle = 0; $cycle < $#blinker; $cycle++)
		  {		  
		    $numblink = $numblink + $blinker[$cycle];
		  }
		$subblink = $subblink + $numblink;
		$expblink = $expblink + $numblink;
		print FH "$trialnum\t $cond\t $item\t $numblink  \t $shortcount\t $num_comb\t $fixcount\t $newfixcount\t"; #fixlister[3] is the start time
		for ($i = 1; $i <= $a; $i++)
		  {
		    print FH "$finfixlistP[$i]\t";
		  }
		print FH "\n"; 
	      }
	    $displayon = 0;
	    $trialnum=$trialnum+1;
	    $trialokflag = 0;
	    $done = 0;
	  }	
      }
    print ">>>>>finished file: $filename<<<<<\n";
    if ( ($blinklong eq "y")||($blinklong eq "Y"))
      {
	print "Total number of fixations for $filename = $subfixnum\n";
	print "Total number of fixations over $longcut ms for $filename = $sublong\n";
	print "Total number of fixations under $ms_comb ms for $filename = $subshort\n";
	print "Total number of combined fixations for $filename = $subcomb\n";
	print "Total number of blinks for $filename = $subblink\n";
	print "Total trials excluded for blinks for $filename = $subblinkbad\n";
	print "Total trials excluded for long fixations for $filename = $sublongbad\n";
	print SFILE "Total number of fixations for $filename = $subfixnum\n";
	print SFILE "Total number of fixations over $longcut ms for $filename = $sublong\n";
	print SFILE "Total number of fixations under $ms_comb ms for $filename = $subshort\n";
	print SFILE "Total number of combined fixations for $filename = $subcomb\n";
	print SFILE "Total number of blinks for $filename = $subblink\n";
	print SFILE "Total trials excluded for blinks for $filename = $subblinkbad\n";
	print SFILE "Total trials excluded for long fixations for $filename = $sublongbad\n\n";
      }
    close INFILE;
    close FH;
  }# this is the end of the while loop that runs the list file stuff
print ">>>>>finished all files<<<<<\n";
if ( ($blinklong eq "y")||($blinklong eq "Y"))
  {
    print "Total number of fixations for experiment = $expfixnum\n";
    print "Total number of fixations over $longcut ms for experiment = $explong\n";
    print "Total number of fixations under $ms_comb ms for experiment = $expshort\n";
    print "Total number of combined fixations for experiment = $expcomb\n";
    print "Total number of blinks for experiment = $expblink\n";
    print "Total trials excluded for blinks = $expblinkbad\n";
    print "Total trials excluded for long fixations = $explongbad\n";
    print SFILE "Total number of fixations for experiment = $expfixnum\n";
    print SFILE "Total number of fixations over $longcut ms for experiment = $explong\n";
    print SFILE "Total number of fixations under $ms_comb ms for experiment = $expshort\n";
    print SFILE "Total number of combined fixations for experiment = $expcomb\n";
    print SFILE "Total number of blinks for experiment = $expblink\n";
    print SFILE "Total trials excluded for blinks = $expblinkbad\n";
    print SFILE "Total trials excluded for long fixations = $explongbad\n\n";
  }
close SFILE;
<>
  
