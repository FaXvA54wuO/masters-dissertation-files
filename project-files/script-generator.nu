#!/usr/bin/env nu
# generate_acquisition.nu
#
# Generates an acquisition script from:
#   1) a profile YAML (contains platform specific:
#        - preamble
#        - postamble
#        - ordered list of task IDs
#   2) a directory of task YAML files (one task per file; each has id + output_path + script)
#
# Assumptions:
# - Profile `tasks` is a list of IDs ONLY.
#
# Usage:
#   nu generate_acquisition.nu {profile file} {tasks directory} {output script name}
#
# Example:
#   nu generate_acquisition.nu kb/profiles/alpine-acquisition-v1.yaml kb/tasks /tmp/alpine_triage.sh

def main [
  profile_path: string,
  tasks_dir: string,
] {
# -----------------------------
# Load profile
# -----------------------------

def file-message-or-exit [
    status: string
    file_path: path
]: nothing -> nothing {
    match $status {
        'profile missing' => {error make { msg: $"File does not exist: ($file_path)" }}
        'profile invalid' => {error make { msg: $"File data is invalid file does not exist: ($file_path)" }}
        'task missing' => {print $'Task file contains invalid data; script continuing: ($file_path)'}
        'task invalid' => {print $'Task file related not found; script continuing: ($file_path)'}
    }
}

def validate-record [
    file: path
    type: string
    required: list<string>
]: nothing -> record<status:string record: record>  {
    if not ($file | path exists) {
        return {
            status: $'($type) missing'
            record: {}
        }
    }
    # Currently opening a file and checking for fields required
    # CONSIDER :: using nushell's type system to reject invalid record structures
    let record: record = open $file
    if ($required | any {|k| ($record | get -o $k | default "" | str trim | is-empty)}) {
        return {
            status: $'($type) invalid'
            record: {}
        }
    }
    {
        status: ok
        record: $record
    }
}

def validate-task [
    file: path
    required: list<string>
]: nothing -> record {
    let task: record = validate-record $file task $required
    file-message-or-exit $task.status $file
    $task.record
}

def validate-task-list [
]: list -> list {
    # If no valid tasks found, exit script
    if ($in | is-empty) {
        error make { msg: $'No task valid YAML files found in: ($tasks_dir)' }
    }

    # If duplicate tasks found exit script; there should not be duplicate task ids
    # Detail duplicate tasks to user for their information
    let duplicates: list = ($in | get id | uniq -d)

    if ($duplicates | is-not-empty)  {
        error make { msg: $'Duplicate tasks found in task list: ($duplicates | str join "; ")' }
    }
    $in
}

def render-template [
    template: string
]: record -> string {
    $in | transpose k v | reduce -f $template {|i,o|
        $o | str replace -a $"{($i.k)}" ($i.v | into string)
    }
}

const required_profile_fields: list<string> = [
    profile_id
    script_output_name
    script_output_template
    script_output_metadata
    function_name_prefix
    function_template
    function_call_template
    preamble
    postamble
    tasks
]

const required_task_fields: list<string> = [
    id
    output_path
    script
]

print 'Script starting. Validating profile and tasks'

let profile_data: record<status:string record: record> = validate-record $profile_path profile $required_profile_fields


# Determine if the profile has tasks, exit script if empty
file-message-or-exit $profile_data.status $profile_path

if ($profile_data.record | get -o tasks | default [] | length) == 0 {
    error make { msg: $"Profile ($profile_path) is invalid or has no tasks" }
}

let profile: record = $profile_data.record

# Obtain tasks based on the profile's task list
let tasks = $profile | get tasks | each {|task_id|
    # Currently based on task filename naming convention (easy but fragile)
    # CONSIDER :: reading task files and filtering on id field (slow but more reliable)
    let task_file_path = $tasks_dir | path join $'($task_id | str downcase | str replace -a '.' '-').yaml'
    validate-task $task_file_path $required_task_fields | select id output_path script
} | compact | validate-task-list

print 'Generating script'

# -----------------------------
# Render and save script
# -----------------------------

 {
    preamble: $profile.preamble

    # Generate functions string from task list
    # Currently task ID is used as a function name sanitised . -> _
    # CONSIDER :: better id naming convention?? abstracting replacement??
    functions: (
        $tasks | each {|task| {
                function: $'($profile.function_name_prefix)($task.id | str replace -a "." "_")'
                function_body: ($task.script | lines | each {$'  ($in)'} | str join "\n")
            }  | render-template $profile.function_template
        } | str join "\n"
    )

    # Generate function calls string from task list
    calls: (
        $tasks | each {|task|
            {
                id: $task.id
                output_path: ($task.output_path | str trim --right --char '/')
            } | render-template $profile.function_call_template
        } | str join "\n"
    )

    postamble: $profile.postamble

    footer: (
        {
            timestamp: (date now | format date "%+")
            profile_id: $profile.profile_id
            profile_path: $profile_path
            tasks_dir: $tasks_dir
        } | render-template $profile.script_output_metadata
    )
} | render-template $profile.script_output_template | save $profile.script_output_name

print $'Script: ($profile.script_output_name), written to: (pwd)'
}