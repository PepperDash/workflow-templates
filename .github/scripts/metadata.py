import os
import re
import json

def extract_implemented_interfaces(file_content):
    interface_pattern = re.compile(r'class\s+\w+\s*:\s*([^{]+)')
    match = interface_pattern.search(file_content)
    if match:
        items = match.group(1).split(',')
        interfaces = [item.strip() for item in items if item.strip().startswith('I')]
        base_classes = [item.strip() for item in items if not item.strip().startswith('I') and not item.strip().startswith('EssentialsPluginDeviceFactory')]
        return interfaces, base_classes
    return [], []

def extract_supported_types(file_content):
    # Remove commented lines
    uncommented_content = re.sub(r'//.*', '', file_content)
    
    # Updated regex to match TypeNames initialization
    types_pattern = re.compile(r'TypeNames\s*=\s*new\s*List<string>\(\)\s*{([^}]+)}')
    matches = types_pattern.findall(uncommented_content)
    types = []
    for match in matches:
        current_types = [type_name.strip().strip('"') for type_name in match.split(',')]
        types.extend(current_types)

    # Remove duplicates and filter out unnecessary entries
    return list(set(filter(None, types)))

def extract_minimum_essentials_framework_version(file_content):
    # Update the regex to exclude comments or anything unnecessary.
    version_pattern = re.compile(r'^\s*MinimumEssentialsFrameworkVersion\s*=\s*"([^"]+)"\s*;', re.MULTILINE)
    match = version_pattern.search(file_content)
    if match:
        return match.group(1)
    return None

def extract_public_methods(file_content):
    methods_pattern = re.compile(r'public\s+\w+\s+\w+\s*\([^)]*\)\s*')
    matches = methods_pattern.findall(file_content)
    return [match.strip() for match in matches]

def read_files_in_directory(directory):
    all_interfaces = []
    all_base_classes = []
    all_supported_types = []
    all_minimum_versions = []
    all_public_methods = []
    all_joins = []

    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.cs'):
                file_path = os.path.join(root, file)
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    interfaces, base_classes = extract_implemented_interfaces(content)
                    supported_types = extract_supported_types(content)
                    minimum_version = extract_minimum_essentials_framework_version(content)
                    public_methods = extract_public_methods(content)

                    all_interfaces.extend(interfaces)
                    all_base_classes.extend(base_classes)
                    all_supported_types.extend(supported_types)
                    if minimum_version:
                        all_minimum_versions.append(minimum_version)
                    all_public_methods.extend(public_methods)

    return {
        "interfaces": all_interfaces,
        "base_classes": all_base_classes,
        "supported_types": all_supported_types,
        "minimum_versions": all_minimum_versions,
        "public_methods": all_public_methods
    }

def read_class_names_and_bases_from_files(directory):
    print("\nScanning for class definitions...")
    class_defs = {}
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.cs'):
                file_path = os.path.join(root, file)
                print(f"\nReading CS file: {file_path}")
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                        if "JoinMapBase" in content or "BridgeJoinMap" in content:
                            print(f"Found potential JoinMap file: {file}")
                        # Rest of the existing processing...
                        class_pattern = re.compile(
                            r'^\s*(?:\[[^\]]+\]\s*)*'
                            r'(?:public\s+|private\s+|protected\s+)?'
                            r'(?:partial\s+)?'
                            r'class\s+([A-Za-z_]\w*)'
                            r'(?:\s*:\s*([^\n{]+))?'
                            r'\s*\{',
                            re.MULTILINE
                        )
                        for match in class_pattern.finditer(content):
                            class_name = match.group(1)
                            bases = match.group(2)
                            if bases:
                                base_classes = [b.strip() for b in bases.split(',')]
                            else:
                                base_classes = []
                            class_defs[class_name] = base_classes
                            print(f"Found class: {class_name} with bases: {base_classes}")
                except Exception as e:
                    print(f"Error reading file {file_path}: {str(e)}")
    return class_defs

def find_joinmap_classes(class_defs):
    print("\nSearching for JoinMap classes...")
    joinmap_classes = []
    for class_name, base_classes in class_defs.items():
        print(f"Checking class: {class_name}")
        print(f"Base classes: {base_classes}")
        
        # Convert the found class name to match file naming convention
        file_class_name = class_name.replace("OneBeyond", "1Beyond")
        
        is_joinmap = (any('JoinMapBase' in base for base in base_classes) or 
                     'BridgeJoinMap' in class_name or 
                     any('JoinMapBaseAdvanced' in base for base in base_classes))
        if is_joinmap:
            print(f"Found JoinMap class: {class_name}")
            joinmap_classes.append(file_class_name)
    return joinmap_classes

def find_file_in_directory(filename, root_directory):
    print(f"\nSearching for file: {filename}")
    print(f"Starting search in directory: {root_directory}")
    
    # Handle variations of the filename
    possible_names = [
        filename,  # Original name
        filename.replace("OneBeyond", "1Beyond"),  # Replace OneBeyond with 1Beyond
        filename.upper(),  # All uppercase
        filename.lower(),  # All lowercase
    ]
    
    for root, _, files in os.walk(root_directory):
        print(f"\nChecking directory: {root}")
        print(f"Files in directory: {files}")
        
        for file in files:
            # Check against all possible variations
            for possible_name in possible_names:
                if file.lower() == possible_name.lower():
                    full_path = os.path.join(root, file)
                    print(f"Found file at: {full_path}")
                    return full_path
    
    print(f"File not found: {filename}")
    return None

def parse_joinmap_info(class_name, root_directory):
    print(f"\nParsing JoinMap info for class: {class_name}")
    filename = f"{class_name}.cs"
    file_path = find_file_in_directory(filename, root_directory)

    if not file_path:
        print(f"File not found: {filename}. Skipping...")
        return []

    print(f"Processing file: {file_path}")
    with open(file_path, 'r', encoding='utf-8') as file:
        file_content = file.read()
        print(f"File size: {len(file_content)} characters")

    # Remove C# comments to avoid false matches
    file_content = re.sub(r'//.*?\n|/\*.*?\*/', '', file_content, flags=re.DOTALL)

    # Split into regions first
    regions = re.split(r'#region\s+(Digital|Analog|Serial)', file_content)[1:]  # Skip the first split which is before first region
    
    joinmap_info = []
    
    # Process regions in pairs (region name and content)
    for i in range(0, len(regions), 2):
        if i + 1 >= len(regions):
            break
            
        region_type = regions[i].strip()
        region_content = regions[i + 1]
        
        # Find the end of the region
        region_content = region_content.split('#endregion')[0]
        
        # Simpler pattern to match individual joins
        join_matches = re.finditer(
            r'\[JoinName\("(?P<name>[^"]+)"\)\][\s\n]*'
            r'public\s+JoinDataComplete\s+\w+\s*=\s*new\s+JoinDataComplete\s*\('
            r'[\s\n]*new\s+JoinData\s*\{[^}]*?JoinNumber\s*=\s*(?P<number>\d+)[^}]*\}'
            r'[\s\n]*,[\s\n]*new\s+JoinMetadata\s*\{[^}]*?Description\s*=\s*"(?P<description>[^"]+)"[^}]*\}',
            region_content,
            re.DOTALL
        )

        for match in join_matches:
            join_info = {
                "name": match.group('name'),
                "join_number": match.group('number'),
                "description": match.group('description'),
                "type": region_type
            }
            print(f"Found join: {join_info}")
            joinmap_info.append(join_info)

    # Sort joins by type and number
    joinmap_info.sort(key=lambda x: (x['type'], int(x['join_number'])))
    print(f"Total joins found: {len(joinmap_info)}")
    return joinmap_info

def generate_markdown_chart(joins, section_title):
    if not joins:
        return ''
    
    markdown_chart = f'### {section_title}\n\n'

    # Group joins by type
    joins_by_type = {'Digital': [], 'Analog': [], 'Serial': []}
    for join in joins:
        join_type = join['type']
        joins_by_type[join_type].append(join)

    # Process each join type in order
    for join_type in ['Digital', 'Analog', 'Serial']:
        if joins_by_type[join_type]:
            markdown_chart += f"#### {join_type}s\n\n"
            markdown_chart += "| Join | Description |\n"
            markdown_chart += "|------|-------------|\n"
            
            # Sort joins by join number
            sorted_joins = sorted(joins_by_type[join_type], key=lambda x: int(x['join_number']))
            
            for join in sorted_joins:
                # Clean up the description
                description = join['description'].strip().replace('|', '\\|')
                # Remove any newlines or extra spaces in description
                description = ' '.join(description.split())
                markdown_chart += f"| {join['join_number']} | {description} |\n"
            
            markdown_chart += '\n'

    return markdown_chart

def generate_config_example_markdown(sample_config):
    markdown = "### Config Example\n\n"
    markdown += "```json\n"
    markdown += json.dumps(sample_config, indent=4)
    markdown += "\n```\n"
    return markdown

def generate_markdown_list(items, section_title):
    """
    Generates a markdown header and list of items.

    Parameters:
    - items (list): The list of items to include.
    - section_title (str): The header for the section.

    Returns:
    - str: The markdown content with the section header.
    """
    if not items:
        return ''
    markdown = f'### {section_title}\n\n'
    for item in items:
        markdown += f"- {item}\n"
    markdown += '\n'
    return markdown

def parse_all_classes(directory):
    class_defs = {}
    class_pattern = re.compile(
        r'^\s*(?:\[[^\]]+\]\s*)*'      # Optional attributes
        r'(?:public\s+|private\s+|protected\s+)?'  # Access modifier
        r'(?:partial\s+)?'                # Optional 'partial' keyword
        r'class\s+([A-Za-z_]\w*)'       # Class name
        r'(?:\s*:\s*[^\{]+)?'           # Optional inheritance
        r'\s*\{',                       # Opening brace
        re.MULTILINE
    )
    property_pattern = re.compile(
        r'^\s*'
        r'(?:\[[^\]]*\]\s*)*'              # Optional attributes
        r'(?:public|private|protected)\s+'  # Access modifier
        r'(?:static\s+|virtual\s+|override\s+|abstract\s+|readonly\s+)?'  # Optional modifiers
        r'([A-Za-z0-9_<>,\s\[\]\?]+?)\s+'     # Type
        r'([A-Za-z_]\w*)\s*'                # Property name
        r'\{[^}]*?\}',                      # Property body
        re.MULTILINE | re.DOTALL
    )
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.cs'):
                file_path = os.path.join(root, file)
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    # Find all class definitions
                    for class_match in class_pattern.finditer(content):
                        class_name = class_match.group(1)
                        class_start = class_match.end()
                        # Find the matching closing brace for the class
                        class_body, end_index = extract_class_body(content, class_start)
                        # Parse properties within the class body
                        properties = []
                        for prop_match in property_pattern.finditer(class_body):
                            prop_string = prop_match.group(0)
                            json_property_match = re.search(r'\[JsonProperty\("([^"]+)"\)\]', prop_string)
                            json_property_name = json_property_match.group(1) if json_property_match else None
                            prop_type = prop_match.group(1).strip()
                            prop_name = prop_match.group(2)
                            properties.append({
                                "json_property_name": json_property_name if json_property_name else prop_name,
                                "property_name": prop_name,
                                "property_type": prop_type
                            })
                        class_defs[class_name] = properties
    return class_defs

def extract_class_body(content, start_index):
    """
    Extracts the body of a class from the content, starting at start_index.
    Returns the class body and the index where it ends.
    """
    brace_count = 1
    index = start_index
    while brace_count > 0 and index < len(content):
        if content[index] == '{':
            brace_count += 1
        elif content[index] == '}':
            brace_count -= 1
        index += 1
    return content[start_index:index - 1], index - 1

def generate_sample_value(property_type, class_defs, processed_classes=None):
    if processed_classes is None:
        processed_classes = set()
    property_type = property_type.strip()
    # Handle nullable types
    property_type = property_type.rstrip('?')
    # Handle primitive types
    if property_type in ('int', 'long', 'float', 'double', 'decimal'):
        return 0
    elif property_type == 'string':
        return "SampleString"
    elif property_type == 'bool':
        return True
    elif property_type == 'DateTime':
        return "2021-01-01T00:00:00Z"
    # Handle collections
    elif property_type.startswith('List<') or property_type.startswith('IList<') or property_type.startswith('IEnumerable<') or property_type.startswith('ObservableCollection<'):
        inner_type = property_type[property_type.find('<')+1:-1]
        return [generate_sample_value(inner_type, class_defs, processed_classes)]
    elif property_type.startswith('Dictionary<'):
        types = property_type[property_type.find('<')+1:-1].split(',')
        key_type = types[0].strip()
        value_type = types[1].strip()
        key_sample = generate_sample_value(key_type, class_defs, processed_classes)
        value_sample = generate_sample_value(value_type, class_defs, processed_classes)
        return { key_sample: value_sample }
    # Handle custom classes
    elif property_type in class_defs:
        if property_type in processed_classes:
            return {}
        processed_classes.add(property_type)
        properties = class_defs[property_type]
        sample_obj = {}
        for prop in properties:
            prop_name = prop['json_property_name']
            prop_type = prop['property_type']
            sample_obj[prop_name] = generate_sample_value(prop_type, class_defs, processed_classes)
        processed_classes.remove(property_type)
        return sample_obj
    else:
        # Unknown type, default to a sample value
        return "SampleValue"

def generate_sample_config(config_class_name, class_defs, supported_types):
    type_name = config_class_name[:-6]  # Remove 'Config'
    if type_name not in supported_types:
        type_name = supported_types[0] if supported_types else type_name
    config = {
        "key": "GeneratedKey",
        "uid": 1,
        "name": "GeneratedName",
        "type": type_name,
        "group": "Group",
        "properties": generate_sample_value(config_class_name, class_defs)
    }
    return config

def read_readme_file(filepath):
    if not os.path.exists(filepath):
        print(f"README.md file not found at {filepath}. A new file will be created.")
        return ""
    with open(filepath, 'r', encoding='utf-8') as f:
        return f.read()

def update_readme_section(readme_content, section_title, new_section_content):
    start_marker = f'<!-- START {section_title} -->'
    end_marker = f'<!-- END {section_title} -->'

    pattern = re.compile(
        rf'{re.escape(start_marker)}(.*?){re.escape(end_marker)}',
        re.DOTALL | re.IGNORECASE
    )

    match = pattern.search(readme_content)

    if match:
        section_content = match.group(1)
        if '<!-- SKIP -->' in section_content:
            print(f"Skipping section: {section_title} (found <!-- SKIP -->)")
            return readme_content  # Return the original content unchanged
        else:
            print(f"Updating existing section: {section_title}")
            updated_section = f'{start_marker}\n{new_section_content.rstrip()}\n{end_marker}'
            updated_readme = readme_content[:match.start()] + updated_section + readme_content[match.end():]
    else:
        print(f"Adding new section: {section_title}")
        # Ensure there's a newline before adding the new section
        if not readme_content.endswith('\n'):
            readme_content += '\n'
        updated_section = f'{start_marker}\n{new_section_content.rstrip()}\n{end_marker}\n'
        updated_readme = readme_content + updated_section
    return updated_readme

def remove_duplicates_preserve_order(seq):
    seen = set()
    return [x for x in seq if not (x in seen or seen.add(x))]

if __name__ == "__main__":
    project_directory = os.path.abspath("./")
    results = read_files_in_directory(project_directory)

    # Remove duplicates from interfaces and base classes while preserving order
    unique_interfaces = remove_duplicates_preserve_order(results["interfaces"])
    unique_base_classes = remove_duplicates_preserve_order(results["base_classes"])

    # Generate markdown sections with titles using the deduplicated lists
    interfaces_markdown = generate_markdown_list(unique_interfaces, "Interfaces Implemented")
    base_classes_markdown = generate_markdown_list(unique_base_classes, "Base Classes")
    supported_types_markdown = generate_markdown_list(results["supported_types"], "Supported Types")
    minimum_versions_markdown = generate_markdown_list(results["minimum_versions"], "Minimum Essentials Framework Versions")
    public_methods_markdown = generate_markdown_list(results["public_methods"], "Public Methods")

    # Generate Join Maps markdown
    class_defs = read_class_names_and_bases_from_files(project_directory)
    joinmap_classes = find_joinmap_classes(class_defs)
    joinmap_info = []
    for cls in joinmap_classes:
        info = parse_joinmap_info(cls, project_directory)
        joinmap_info.extend(info)
    join_maps_markdown = generate_markdown_chart(joinmap_info, "Join Maps")

    # Generate Config Example markdown
    all_class_defs = parse_all_classes(project_directory)
    config_classes = [cls for cls in all_class_defs if cls.endswith('Config') or cls.endswith('ConfigObject')]
    if not config_classes:
        print("No config classes found.")
        config_example_markdown = ""
    else:
        main_config_class = max(config_classes, key=lambda cls: len(all_class_defs[cls]))
        sample_config = generate_sample_config(main_config_class, all_class_defs, results["supported_types"])
        config_example_markdown = generate_config_example_markdown(sample_config)

    # Read the existing README.md content
    readme_path = os.path.join(project_directory, 'README.md')
    readme_content = read_readme_file(readme_path)

    # Update or insert sections with section titles handled in the content
    readme_content = update_readme_section(readme_content, "Minimum Essentials Framework Versions", minimum_versions_markdown)
    if config_example_markdown:
        readme_content = update_readme_section(readme_content, "Config Example", config_example_markdown)
    readme_content = update_readme_section(readme_content, "Supported Types", supported_types_markdown)
    readme_content = update_readme_section(readme_content, "Join Maps", join_maps_markdown)
    readme_content = update_readme_section(readme_content, "Interfaces Implemented", interfaces_markdown)
    readme_content = update_readme_section(readme_content, "Base Classes", base_classes_markdown)
    readme_content = update_readme_section(readme_content, "Public Methods", public_methods_markdown)

    # Write the updated content back to README.md
    with open(readme_path, 'w', encoding='utf-8') as f:
        f.write(readme_content)

    print("README.md has been updated.")