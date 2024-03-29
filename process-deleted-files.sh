source build-and-inspect-files.sh

# Fail on errors (and other things)
set -euo pipefail

if [[ "$DEBUG" == true ]]
then
    set -x    
fi

echo "has_outputs=false" >> $GITHUB_OUTPUT

mapfile -d ',' -t deleted_files < <(printf "%s," "$FILES_REMOVED")

deleted_files+=(${excluded_files[@]})

# Sorting deleted files alphabetically so that CSVs get deleted before companion JSON files 
# ensuring the JSON file doesn't come first in which case we'd build the CSV-W again and then immediately delete it.
mapfile -t deleted_files < <(printf "%s\n" "${deleted_files[@]}" | sort)

function delete_csvw_outputs {

    local csv_file="$1"
    local out_path=$(get_out_path "$csv_file")
    
    if [[ -d "$out_path" ]]; then
        echo "Removing $out_path"
        git rm -r "$out_path"
    fi

    if [[ "$COMMIT_OUTPUTS_TO_GH_PAGES" = true ]]
    then
        # Remove the files from the gh-pages branch as well.

        git stash

        # Switch to the gh-pages branch
        git checkout gh-pages

        echo "Removing $out_path from gh-pages branch."

        if [[ -d "$out_path" ]]; then
            git rm -r "$out_path"
        fi

        git stash
        
        # Go back to the original branch/tag we were working on.
        git checkout "$GITHUB_REF_NAME"
        
        local stash_content=$(git stash list)

        if [[ -n "$stash_content" ]]; then # Reapply the changes we stashed from the "$GITHUB_REF_NAME" tag/branch.
            git stash apply stash@{1}
            echo "has_outputs=true" >> $GITHUB_OUTPUT
        else
            echo "stash was empty."
        fi
    fi
}

for file in "${deleted_files[@]}"; do
    echo $'\n'
    echo "---Handling Deletions for File: ${file}"            

    file_extension="${file##*.}"

    if [[ $(get_top_level_folder_name "$file") == "out" ]]
    then
        echo "This is not the file we're looking for. It is located in the output directory."
        continue
    elif [[ $file_extension != "csv" && $file_extension != "json" ]]; then
        echo "This is not the file we're looking for. Neither JSON nor CSV."
        continue
    fi
    
    if [[ $file_extension == "csv" ]]; then
        delete_csvw_outputs "$file"
    elif [[ $file_extension == "json" ]]; then
        config_file="$file"
        csv_file=$(get_companion_csv_file_for_json "$file")

        if [[ -f "$csv_file" ]] && ! is_excluded_file "$csv_file" && [[ "$JSON_CONFIG_REQUIRED" == false ]]
        then
            # The JSON file has been deleted but the csv file still exists so we should rebuild it.
            build_and_inspect_csvw "$csv_file"
        fi
    fi
   
    echo "---Finished Handling Deletions for File: ${file}"
done
