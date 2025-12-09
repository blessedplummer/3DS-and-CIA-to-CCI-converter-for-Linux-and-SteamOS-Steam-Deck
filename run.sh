#!/bin/bash

# --- Setup Environment ---
cd "$(dirname "$0")" || exit 1
# We define the workspace relative to Home to ensure write permissions
WORKSPACE_DIR="$HOME/cia-unix-workspace"
TEMP_EXTRACT="$WORKSPACE_DIR/temp_extraction"

# --- Setup Workspace ---
mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR" || exit 1

# --- 1. Download/Update Tools ---
echo "Checking for tool updates..."
# Fetch latest URL
DOWNLOAD_URL=$(curl -s https://api.github.com/repos/shijimasoft/cia-unix/releases/latest \
| grep "browser_download_url" \
| grep "linux-x86_64.zip" \
| cut -d '"' -f 4)

# Download if missing or new
if [ -n "$DOWNLOAD_URL" ]; then
    ZIP_FILENAME=$(basename "$DOWNLOAD_URL")
    if [ ! -f "$ZIP_FILENAME" ]; then
        echo "Downloading update..."
        curl -L -O "$DOWNLOAD_URL"
        unzip -o "$ZIP_FILENAME"
    fi
fi

# Get helper script
if [ ! -f "dltools.sh" ]; then
    curl -L -o dltools.sh https://raw.githubusercontent.com/shijimasoft/cia-unix/main/dltools.sh
fi
chmod +x dltools.sh

# Run helper to get keys (boot9, seeddb, etc)
./dltools.sh

# --- 2. Select File ---
FILE_PATH=$(zenity --file-selection \
    --title="Select Game or Archive" \
    --file-filter="Supported Files | *.3ds *.cia *.3DS *.CIA *.zip *.ZIP *.7z *.7Z *.rar *.RAR")

if [ -z "$FILE_PATH" ]; then
    echo "Cancelled."
    exit 0
fi

SOURCE_DIR=$(dirname "$FILE_PATH")
FILENAME=$(basename "$FILE_PATH")
EXTENSION="${FILENAME##*.}"
EXTENSION_LOWER="${EXTENSION,,}"

# Prepare temp folder
rm -rf "$TEMP_EXTRACT"
mkdir -p "$TEMP_EXTRACT"

# --- 3. Extract or Copy to Temp ---
echo "------------------------------------------------"
echo "Processing: $FILENAME"
echo "------------------------------------------------"

# Check if it is an archive format supported by 7z
if [[ "$EXTENSION_LOWER" == "zip" || "$EXTENSION_LOWER" == "7z" || "$EXTENSION_LOWER" == "rar" ]]; then
    if command -v 7z &> /dev/null; then
        echo "Extracting Archive using 7z..."
        # 'x' extracts with full paths, '-o' specifies output dir, '-y' assumes yes on prompts
        7z x "$FILE_PATH" -o"$TEMP_EXTRACT" -y
    else
        zenity --error --text="Error: '7z' command not found.\nPlease install p7zip-full (sudo apt install p7zip-full)."
        exit 1
    fi
else
    # Not an archive, just copy the single file to temp
    cp "$FILE_PATH" "$TEMP_EXTRACT/"
fi

# --- 4. Process Files in Workspace ---
# Ensure the tool is executable
chmod +x ./cia-unix

# Find .3ds/.cia files in temp, move them to workspace root, run, then move back
find "$TEMP_EXTRACT" -type f \( -iname "*.3ds" -o -iname "*.cia" \) -print0 | while IFS= read -r -d '' FOUND_FILE; do

    GAME_FILENAME=$(basename "$FOUND_FILE")
    GAME_BASENAME="${GAME_FILENAME%.*}" # Filename without extension

    echo "------------------------------------------------"
    echo "Decrypting: $GAME_FILENAME"
    echo "------------------------------------------------"

    # 1. Move file FROM temp TO current workspace directory
    # This ensures cia-unix finds the file locally
    mv "$FOUND_FILE" .

    # 2. Run the tool on the local file
    ./cia-unix "$GAME_FILENAME"

    # 3. Handle Renaming (A-decrypted.3ds -> A.cci)
    # The tool creates a file named [Name]-decrypted.3ds
    EXPECTED_OUTPUT="${GAME_BASENAME}-decrypted.3ds"
    
    if [ -f "$EXPECTED_OUTPUT" ]; then
        echo "Detected decrypted output: $EXPECTED_OUTPUT"
        echo "Renaming to .cci..."
        mv "$EXPECTED_OUTPUT" "${GAME_BASENAME}.cci"
    fi

    # 4. Move the results back to the user's Source Directory
    
    # Move any .cci files (This catches the renamed file from step 3)
    if ls *.cci 1> /dev/null 2>&1; then
        mv *.cci "$SOURCE_DIR/"
    fi

    # Fallback: If the tool outputted a standard .3ds that wasn't renamed (or from a CIA convert)
    # We ignore the original input file if it's still there
    ls *.3ds 2>/dev/null | while read -r generated_3ds; do
        if [ "$generated_3ds" != "$GAME_FILENAME" ]; then
            mv "$generated_3ds" "$SOURCE_DIR/"
        fi
    done

    # 5. Cleanup: Remove the input file from workspace
    if [ -f "$GAME_FILENAME" ]; then
        rm "$GAME_FILENAME"
    fi

done

# --- 5. Final Cleanup ---
rm -rf "$TEMP_EXTRACT"

echo "------------------------------------------------"
echo "Done!"
echo "Files are in: $SOURCE_DIR"
echo "------------------------------------------------"
zenity --info --text="Process Complete!\nDecrypted files moved to:\n$SOURCE_DIR"

exit 0