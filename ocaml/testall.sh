# Main test script
# Author: Emma Etherington

#!/bin/sh

# Path to the LLVM interpreter
LLI="lli"
#LLI="/usr/local/opt/llvm/bin/lli"

# Path to the LLVM compiler
LLC="llc"

# Path to the C compiler
CC="gcc"

# Path to sake compiler - usually just ./sake.native 
#SAKE="./sake"
SAKE="_build/sake.native"

# Set time limit for all operations
ulimit -t 30

globallog=alltests.log
rm -f $globallog
error=0
globalerror=0
keep=0

# usage
Usage() {
    echo "Usage: tests.sh [.sk file]"
    echo "-k    Keep the intermediate files"
    exit 1
}

# SignalError()
SignalError() {    
    if [ $error -eq 0 ] ; then            
        echo "FAILED"                    
        error=1                     
    fi               
    echo "  $1"      
}

# Comparing the generated with expected 
Compare() {    
    generatedfiles="$generatedfiles $3"           
    echo diff -b $1 $2 ">" $3 1>&2        
    diff -b "$1" "$2" > "$3" 2>&1 || {
        SignalError "$1 differs"
        echo "FAILED $1 differs from $2" 1>&2   
    }                                
}

# Run functions -> how we want run it and then report errors 
Run() {
    echo $* 1>&2
    #echo $*
    eval $* || {
        SignalError "$1 failed on $*"
        return 1
    }
}

RunFail() {
    echo $* 1>&2
    eval $* && {
        SignalError "Failed: $* did not report an error"
        return 1
    }
    return 0    
}

# Check functions -> should be calling run() funcs and compare() funcs 
Check() {

    error=0   
    basename=`echo $1 | sed 's/.*\\///
                             s/.sk//'`
    reffile=`echo $1 | sed 's/.sk$//'`    
    basedir="`echo $1 | sed 's/\/[^\/]*$//'`/."

    #echo $wrapper 
    #echo "../testing/$wrapper"

    echo -n "$basename..."
    echo 1>&2     
    echo "###### Testing $basename" 1>&2

    generatedfiles="" 

    if [ ! -f "../testing/${basename}.c" ]; then
        #error=2
        #echo "FAILED NO WRAPPER"  

        echo "#include <stdio.h>" > ../testing/${basename}.c
        echo "#include <stdlib.h>" >> ../testing/${basename}.c
        echo "#include <unistd.h>" >> ../testing/${basename}.c
        echo "#include \"${basename}.h\"\n" >> ../testing/${basename}.c
        echo "int main() {\n\tstruct ${basename}_input i;" >> ../testing/${basename}.c
        echo "\tstruct ${basename}_state s;" >> ../testing/${basename}.c
        echo "\n\t${basename}_tick(&s, NULL, NULL); \n\t${basename}_tick(&s, &i, NULL); \n\n\treturn 0;\n}" >> ../testing/${basename}.c

        generatedfiles="$generatedfiles ${basename}.ll ${basename}.s ${basename}.exe ${basename}.out ${basename}.o" && 
        Run "$SAKE" " " $1 ${basename} &&
        Run "mv ${basename}.h ../testing/" &&
        Run "$LLC" "${basename}.ll" ">" "${basename}.s" &&
        Run "$CC" "-c" "../testing/${basename}.c ../testing/${basename}.h" && 
        Run "$CC" "-o" "${basename}.exe" "${basename}.s" "${basename}.o" "print.o" &&                    
        Run "./${basename}.exe" > "${basename}.out" &&
        Compare ${basename}.out ${reffile}.out ${basename}.diff
    else
        generatedfiles="$generatedfiles ${basename}.ll ${basename}.s ${basename}.exe ${basename}.out ${basename}.o" &&     
        Run "$SAKE" " " $1 ${basename} &&
        Run "mv ${basename}.h ../testing/" &&
        Run "$LLC" "${basename}.ll" ">" "${basename}.s" &&
        Run "$CC" "-c" "../testing/${basename}.c ../testing/${basename}.h" && 
        Run "$CC" "-o" "${basename}.exe" "${basename}.s" "${basename}.o" "print.o" &&                    
        Run "./${basename}.exe" > "${basename}.out" &&
        Compare ${basename}.out ${reffile}.out ${basename}.diff
    fi
    

    # Report the status and clean up the generated files
    if [ $error -eq 0 ] ; then
        if [ $keep -eq 0 ] ; then
            rm -f $generatedfiles
        fi
        echo "OK"
        echo "###### SUCCESS" 1>&2
    else 
        echo "###### FAILED" 1>&2
        globalerror=$error
    fi
}

CheckFail() {

    error=0   
    basename=`echo $1 | sed 's/.*\\///
                             s/.sk//'`
    reffile=`echo $1 | sed 's/.sk$//'`    
    basedir="`echo $1 | sed 's/\/[^\/]*$//'`/."

    echo -n "$basename..."

    echo 1>&2     
    echo "###### Testing $basename" 1>&2
  
    generatedfiles="" 

    generatedfiles="$generatedfiles ${basename}.err ${basename}.diff" &&
    RunFail "$SAKE" " " $1 ${basename} "2>" "${basename}.err" ">>" $globallog &&     
    Compare ${basename}.err ${reffile}.err ${basename}.diff
     
    # Report the status and clean up the generated files
    if [ $error -eq 0 ] ; then
        if [ $keep -eq 0 ] ; then
            rm -f $generatedfiles
        fi
        echo "OK"
        echo "###### SUCCESS" 1>&2
    else
        echo "###### FAILED" 1>&2
        globalerror=$error
    fi
}

# CHECK FOR FLAGS 
while getopts kdpsh c; do
    case $c in
        k) # Keep intermediate files
            keep=1
            ;;
    esac
done

shift `expr $OPTIND - 1`

LLIFail() {  
    echo "Could not find the LLVM interpreter \"$LLI\"." 
    echo "Check your LLVM installation and/or modify the LLI variable in testall.sh"
    exit 1
}

which "$LLI" >> $globallog || LLIFail

if [ ! -f print.o ]
then        
    echo "Could not find print.o"   
    echo "Try \"make print.o\""
    exit 1
fi

# CODE TO GET THE TEST FILES

if [ $# -ge 1 ] 
then
    files=$@
else
    #Check this path 
    files="../testing/test_*.sk ../testing/fail_*.sk"
fi

# RUN CHECKS 

for file in $files 
do
    case $file in
        *test_*TL*) 
            ;; # Don't run the traffic light programs becuase they have sleeps in 
        *test_*)
            Check $file 2>> $globallog 
            ;;
        *fail_*)
            CheckFail $file 2>> $globallog
            ;;
        *)
            echo "unkown file type $file"
            globalerror=1
            ;;
    esac
done


exit $globalerror
