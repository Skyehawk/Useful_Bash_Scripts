#!/bin/bash

# Enable extended globbing
shopt -s extglob

# Function to display help
display_help() {
    echo "File Shifter Script"
    echo "This script shifts filenames containing integers by a specified integer value."
    echo
    echo "Usage: $0 <file_path_pattern> <signed integer> [-v]"
    echo
    echo "Arguments:"
    echo "  <file_path_pattern>  Pattern to match the files to be renamed."
    echo "  <signed integer>     Integer by which to shift the filenames."
    echo "  -v                   Enable verbose mode."
    echo
    echo "Examples:"
    echo "  $0 './file[0-9]*.txt' 1"
    echo "    Shifts filenames matching './file[0-9]*.txt' by 1. For example, 'file1.txt' becomes 'file2.txt'."
    echo
    echo "  $0 './file[0-9]*.txt' -1"
    echo "    Shifts filenames matching './file[0-9]*.txt' by -1. For example, 'file2.txt' becomes 'file1.txt'."
    echo
    echo "  $0 './item-[0-9]*.log' 10"
    echo "    Shifts filenames matching './item-[0-9]*.log' by 10. For example, 'item-5.log' becomes 'item-15.log'."
    echo
    echo "Note: This script only modifies the integer (and negative sign denoted by '-') at the end of the file name."
    echo "      It doesn't modify integers in the extension or earlier on in the filename."
}

# Function to show progress when not in verbose mode
show_progress() {
    local count=$1
    local total=$2

    #HACK:
   # We loop through twice and add 1 each time (temp file names and final file names), so to avoid 200% we divide by 2.
   # We call this in each iteration of each loop to accuratly reflect the progress of the shift process. 
   # This doesn't impact anything other than the progress bar, there are definatally better ways to do this.
    local progress=$(( ($count * 100) / $total ))
    local completed=$(( $progress / 2 ))
    local remaining=$(( 50 - $completed ))

    printf "\rProgress: ["
    for ((i=0; i<$completed; i++)); do
        printf "#"
    done
    for ((i=0; i<$remaining; i++)); do
        printf "-"
    done
    printf "] %d%%" $progress
}

# Check if the help option is passed
if [[ "$1" == "-help" ]]; then
    display_help
    exit 0
fi

# Check if the correct number of arguments were passed
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    display_help
    exit 1
fi

# Get the file path pattern and integer from the arguments
FILE_PATH_PATTERN=$1
SHIFT_INT=$2

# Validate SHIFT_INT is indeed an integer (allows for negative numbers)
if ! [[ "$SHIFT_INT" =~ ^-?[0-9]+$ ]]; then
    echo "Error: The second argument must be an integer."
    exit 1
fi

# Default options
VERBOSE=0

# Process optional flags
shift 2
while [ "$#" -gt 0 ]; do
    case "$1" in
        -v)
            VERBOSE=1
            ;;
        *)
            display_help
            exit 1
            ;;
    esac
    shift
done

# Function to extract the last integer from the filename
get_last_integer() {
    local filename="$1"
    local basename=$(basename "$filename")
    local name="${basename%.*}"
    if [[ "$name" =~ -?[0-9]+$ ]]; then
        echo "${name##*[!0-9-]}"
    else
        echo "0"
    fi
}

# Expand the file path pattern to match files
FILES=($(compgen -G "$FILE_PATH_PATTERN"))

# Check if any files match the pattern
if [ ${#FILES[@]} -eq 0 ]; then
    echo "No files found matching the pattern $FILE_PATH_PATTERN."
    exit 1
fi

# Sort files based on the last integer in the filename
FILES_SORTED=()
for FILE in "${FILES[@]}"; do
    LAST_INT=$(get_last_integer "$FILE")
    FILES_SORTED+=("$LAST_INT:$FILE")
done

IFS=$'\n' FILES_SORTED=($(sort -t ':' -k1n <<<"${FILES_SORTED[*]}" | cut -d ':' -f2-))

# Determine the order based on SHIFT_INT
if [ "$SHIFT_INT" -gt 0 ]; then
    # Positive shift: Start from largest to smallest
    FILES_SORTED=($(printf '%s\n' "${FILES_SORTED[@]}" | sort -r))
else
    # Negative shift: Start from smallest to largest
    FILES_SORTED=($(printf '%s\n' "${FILES_SORTED[@]}"))
fi

# Print sorted FILES and SHIFT_INT if verbose mode
if [ $VERBOSE -eq 1 ]; then
    echo "Files to be processed:"
    for FILE in "${FILES_SORTED[@]}"; do
        echo "$FILE"
    done
    echo "Integer to shift filenames by: $SHIFT_INT"
fi

# Create an associative array to hold original and new names
declare -A FILE_MAP

# Create an array to hold temporary names
declare -A TEMP_MAP

# Process each file to determine new names
COUNT=0
TOTAL=$(( ${#FILES_SORTED[@]} * 2 ))  # Total steps (renaming to temp and final names)

if [ $VERBOSE -eq 0 ]; then
    echo -n "Renaming files: "
fi

LINE_COUNT=0
for FILE in "${FILES_SORTED[@]}"; do
    BASENAME=$(basename "$FILE")
    DIRNAME=$(dirname "$FILE")
    EXTENSION="${BASENAME##*.}"
    NAME="${BASENAME%.*}"

    # Find the last integer in the file name
    LAST_INT=$(get_last_integer "$FILE")
    
    # Remove leading zeros if any
    LAST_INT=${LAST_INT#0}

    # Add SHIFT_INT, ensuring to remove leading zeros if any
    NEW_INT=$((10#$LAST_INT + SHIFT_INT))

    # Check if the new integer exceeds the signed integer limit
    MAX_INT=2147483647
    MIN_INT=-2147483648
    if [ "$NEW_INT" -gt "$MAX_INT" ] || [ "$NEW_INT" -lt "$MIN_INT" ]; then
        echo "Error: The new integer value for $FILE exceeds the 32-bit signed integer limit. Skipping..."
        continue
    fi

    # Replace the last occurrence of the integer in the name
    NEW_NAME="${NAME%"$LAST_INT"}$NEW_INT"

    FINAL_NEW_FILE="$DIRNAME/$NEW_NAME.$EXTENSION"

    # Create a temporary name
    TEMP_FILE="$DIRNAME/tmp_$BASENAME"

    # Map original file to temporary name
    TEMP_MAP["$FILE"]="$TEMP_FILE"

    # Map temporary name to new name
    FILE_MAP["$TEMP_FILE"]="$FINAL_NEW_FILE"

    if [ $VERBOSE -eq 1 ]; then
        echo "Processing: $FILE"
    fi

    # Rename file to temporary name
    mv "$FILE" "$TEMP_FILE"
    ((COUNT++))

    if [ $VERBOSE -eq 0 ]; then
        show_progress $COUNT $TOTAL
    fi

    if [ $LINE_COUNT -lt 100 ]; then
        ((LINE_COUNT++))
    elif [ $LINE_COUNT -eq 100 ]; then
        echo "..."
        ((LINE_COUNT++))
    fi
done

if [ $VERBOSE -eq 1 ]; then
    echo "Renaming completed."
fi

# Rename temporary files to final names
for TEMP_FILE in "${!FILE_MAP[@]}"; do
    FINAL_NEW_FILE=${FILE_MAP[$TEMP_FILE]}
    mv "$TEMP_FILE" "$FINAL_NEW_FILE"
    ((COUNT++))

    if [ $VERBOSE -eq 0 ]; then
        show_progress $COUNT $TOTAL
    fi

    if [ $LINE_COUNT -lt 100 ]; then
        ((LINE_COUNT++))
    elif [ $LINE_COUNT -eq 100 ]; then
        echo "..."
        ((LINE_COUNT++))
    fi
done

# EOF

