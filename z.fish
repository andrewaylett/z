# z.fish - fish port of z.sh

# Set up default values if not already set
set -q _Z_CMD; or set -gx _Z_CMD "z"
set -q _Z_DATA; or set -gx _Z_DATA "$HOME/.z"
set -q _Z_MAX_SCORE; or set -gx _Z_MAX_SCORE 9000

# Check if datafile is a directory
if test -d $_Z_DATA
    echo "ERROR: z.fish's datafile ($_Z_DATA) is a directory."
end

function _z -d "Jump to a recent directory."
    set -l datafile "$_Z_DATA"

    # Handle symlinks
    if test -L "$datafile"
        set datafile (readlink "$datafile")
    end

    # Bail if we don't own datafile and $_Z_OWNER not set
    if test -z "$_Z_OWNER"; and test -f "$datafile"; and not test (id -u) = (stat -f %u "$datafile")
        return
    end

    # Add entry
    if test "$argv[1]" = "--add"
        set -e argv[1]
        set -l dir $argv
        
        # Skip if it's $HOME or root
        if test "$dir" = "$HOME" -o "$dir" = "/"
            return
        end

        # Check excluded directories
        if set -q _Z_EXCLUDE_DIRS
            for exclude in $_Z_EXCLUDE_DIRS
                if string match -q "$exclude*" -- $dir
                    return
                end
            end
        end

        # Add entry to datafile
        set -l tempfile "$datafile.$RANDOM"
        
        if test -f "$datafile"
            awk -v path="$dir" -v now=(date +%s) -v score=$_Z_MAX_SCORE -F"|" '
                BEGIN {
                    rank[path] = 1
                    time[path] = now
                }
                $2 >= 1 {
                    if( $1 == path ) {
                        rank[$1] = $2 + 1
                        time[$1] = now
                    } else {
                        rank[$1] = $2
                        time[$1] = $3
                    }
                    count += $2
                }
                END {
                    if( count > score ) {
                        for( x in rank ) print x "|" 0.99*rank[x] "|" time[x]
                    } else for( x in rank ) print x "|" rank[x] "|" time[x]
                }
            ' "$datafile" 2>/dev/null >$tempfile
            
            if test $status -eq 0
                mv -f "$tempfile" "$datafile"
            else
                rm -f "$tempfile"
            end
        else
            echo "$dir|1|"(date +%s) >$datafile
        end

    # Complete
    else if test "$argv[1]" = "--complete"
        if test -f "$datafile"
            while read -l line
                set -l dir (string split '|' $line)[1]
                if test -d "$dir"
                    echo $dir
                end
            end < "$datafile"
        end

    # List/Search
    else
        set -l typ
        set -l list
        set -l echo
        set -l fnd

        # Parse options
        set -l options "h/help" "l/list" "r/rank" "t/recent" "e/echo" "c/current" "x/delete"
        argparse $options -- $argv

        if set -q _flag_help
            echo "Usage: $_Z_CMD [-cehlrtx] args..." >&2
            return
        end

        set -q _flag_list; and set list 1
        set -q _flag_echo; and set echo 1
        set -q _flag_rank; and set typ "rank"
        set -q _flag_recent; and set typ "recent"
        
        if set -q _flag_current
            set fnd "^$PWD $fnd"
        end

        if set -q _flag_delete
            sed -i -e "\:^$PWD|.*:d" "$datafile"
            return
        end

        # Build search string from remaining arguments
        for arg in $argv
            set fnd "$fnd $arg"
        end
        set fnd (string trim "$fnd")

        [ -f "$datafile" ]; or return

        set -l cd (while read -l line
            set -l parts (string split '|' $line)
            set -l dir $parts[1]
            set -l rank $parts[2]
            set -l time $parts[3]

            if test -d $dir
                if string match -q -- "*$fnd*" $dir
                    echo "$rank|$time|$dir"
                end
            end
        end < "$datafile" | sort -n -r | head -n 1 | cut -d'|' -f3)

        if test -n "$cd"
            if test -n "$echo"
                echo "$cd"
            else
                cd "$cd"
            end
        end
    end
end

# Register completions
complete -c $_Z_CMD -a "(_z --complete (commandline -t))"

# Add directory on directory change
function _z_on_pwd --on-variable PWD
    status --is-command-substitution; and return
    _z --add "$PWD" &
end