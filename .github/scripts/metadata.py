import os
import re
import json
import logging

# Set up logging configuration
logging.basicConfig(level=logging.DEBUG)

def extract_implemented_interfaces(file_content):
    logging.debug("Extracting implemented interfaces and base classes.")
    interface_pattern = re.compile(r'class\s+\w+\s*:\s*([^{]+)')
    match = interface_pattern.search(file_content)
    if match:
        logging.debug("Inheritance pattern matched in class definition.")
        items = match.group(1).split(',')
        interfaces = [item.strip() for item in items if item.strip().startswith('I')]
        base_classes = [
            item.strip()
            for item in items
            if not item.strip().startswith('I') and not item.strip().startswith('EssentialsPluginDeviceFactory')
        ]
        logging.debug(f"Interfaces extracted: {interfaces}")
        logging.debug(f"Base classes extracted: {base_classes}")
        return interfaces, base_classes
    logging.debug("No implemented interfaces or base classes found.")
    return [], []

def extract_supported_types(file_content):
    logging.debug("Extracting supported types.")
    # Remove commented lines
    uncommented_content = re.sub(r'//.*', '', file_content)
    
    # Updated regex to match TypeNames initialization
    types_pattern = re.compile(r'TypeNames\s*=\s*new\s*List<string>\(\)\s*{([^}]+)}')
    matches = types_pattern.findall(uncommented_content)
    types = []
    for match in matches:
        current_types = [type_name.strip().strip('"') for type_name in match.split(',')]
        types.extend(current_types)
        logging.debug(f"Current types extracted: {current_types}")

    # Remove duplicates and filter out unnecessary entries
    unique_types = list(set(filter(None, types)))
    logging.debug(f"Unique supported types: {unique_types}")
    return unique_types

def extract_minimum_essentials_framework_version(file_content):
    logging.debug("Extracting minimum Essentials Framework version.")
    version_pattern = re.compile(r'^\s*MinimumEssentialsFrameworkVersion\s*=\s*"([^"]+)"\s*;', re.MULTILINE)
    match = version_pattern.search(file_content)
    if match:
        version = match.group(1)
        logging.debug(f"Minimum Essentials Framework Version found: {version}")
        return version
    logging.debug("No Minimum Essentials Framework Version found.")
    return None

def extract_public_methods(file_content):
    logging.debug("Extracting public methods.")
    methods_pattern = re.compile(r'public\s+\w+\s+\w+\s*\([^)]*\)\s*')
    matches = methods_pattern.findall(file_content)
    methods = [match.strip() for match in matches]
    logging.debug(f"Public methods extracted: {methods}")
    return methods

def read_files_in_directory(directory):
    logging.debug(f"Reading files in directory: {directory}")
    all_interfaces = []
    all_base_classes = []
    all_supported_types = []
    all_minimum_versions = []
    all_public_methods = []

    for root, _, files in os.walk(directory):
        logging.debug(f"Entering directory: {root}")
        for file in files:
            if file.endswith('.cs'):
                file_path = os.path.join(root, file)
                logging.debug(f"Processing file: {file_path}")
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

    logging.debug("Finished reading all files.")
    return {
        "interfaces": all_interfaces,
        "base_classes": all_base_classes,
        "supported_types": all_supported_types,
        "minimum_versions": all_minimum_versions,
        "public_methods": all_public_methods
    }

def read_class_names_and_bases_from_files(directory):
    logging.debug(f"Reading class names and bases from files in directory: {directory}")
    class_defs = {}
    class_pattern = re.compile(
        r'^\s*(?:\[[^\]]+\]\s*)*'        # Optional attributes
        r'(?:public\s+|private\s+|protected\s+)?'  # Optional access modifier
        r'(?:partial\s+)?'                # Optional 'partial' keyword
        r'class\s+([A-Za-z_]\w*)'         # Class name
        r'(?:\s*:\s*([^\{]+))?'           # Optional base classes
        r'\s*\{',                         # Opening brace
        re.MULTILINE
    )
    for root, _, files in os.walk(directory):
        logging.debug(f"Entering directory: {root}")
        for file in files:
            if file.endswith('.cs'):
                file_path = os.path.join(root, file)
                logging.debug(f"Processing file: {file_path}")
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    for match in class_pattern.finditer(content):
                        class_name = match.group(1)
                        bases = match.group(2)
                        if bases:
                            base_classes = [b.strip() for b in bases.split(',')]
                        else:
                            base_classes = []
                        logging.debug(f"Class '{class_name}' with bases: {base_classes}")
                        class_defs[class_name] = base_classes
    logging.debug("Finished reading class definitions.")
    return class_defs

def find_joinmap_classes(class_defs):
    logging.debug("Finding classes that inherit from 'JoinMapBaseAdvanced'.")
    joinmap_classes = []
    for class_name, base_classes in class_defs.items():
        if 'JoinMapBaseAdvanced' in base_classes:
            logging.debug(f"Class '{class_name}' is a JoinMap class.")
            joinmap_classes.append(class_name)
    return joinmap_classes

def find_file_in_directory(filename, root_directory):
    logging.debug(f"Searching for file '{filename}' in directory: {root_directory}")
    for root, _, files in os.walk(root_directory):
        if filename in files:
            full_path = os.path.join(root, filename)
            logging.debug(f"File found: {full_path}")
            return full_path
    logging.debug(f"File '{filename}' not found in directory '{root_directory}'.")
    return None

def parse_joinmap_info(class_name, root_directory):
    logging.debug(f"Parsing join map info for class '{class_name}'.")
    filename = f"{class_name}.cs"
    file_path = find_file_in_directory(filename, root_directory)

    if not file_path:
        logging.warning(f"File not found: {filename}. Skipping...")
        return []

    with open(file_path, 'r', encoding='utf-8') as file:
        file_content = file.read()

    # Remove comments to prevent interference with regex
    file_content = re.sub(r'//.*', '', file_content)
    file_content = re.sub(r'/\*.*?\*/', '', file_content, flags=re.DOTALL)

    # Updated regex to handle multiline definitions and optional parameters
    join_pattern = re.compile(
        r'\[JoinName\("(?P<join_name>[^"]+)"\)\]\s*'                  # [JoinName("...")]
        r'public\s+JoinDataComplete\s+(?P<property_name>\w+)\s*=\s*'   # public JoinDataComplete PropertyName =
        r'new\s+JoinDataComplete\s*\(\s*'                             # new JoinDataComplete(
        r'(?P<join_params>.*?)\)\s*;',                                # Capture everything inside the parentheses
        re.DOTALL
    )

    joinmap_info = []
    for match in join_pattern.finditer(file_content):
        join_name = match.group('join_name')
        property_name = match.group('property_name')
        join_params = match.group('join_params')

        logging.debug(f"Processing join '{join_name}' in property '{property_name}'.")

        # Extract JoinData and JoinMetadata from join_params
        join_data_match = re.search(r'new\s+JoinData\s*(?:\(\s*\))?\s*\{(.*?)\}', join_params, re.DOTALL)
        join_metadata_match = re.search(r'new\s+JoinMetadata\s*(?:\(\s*\))?\s*\{(.*?)\}', join_params, re.DOTALL)

        # Initialize variables
        join_number = None
        description = None
        join_type = None

        if join_data_match:
            join_data_content = join_data_match.group(1)
            join_number_match = re.search(r'JoinNumber\s*=\s*(\d+)', join_data_content)
            if join_number_match:
                join_number = join_number_match.group(1)
                logging.debug(f"Join number found: {join_number}")
            else:
                logging.debug(f"No join number found in join data for '{join_name}'.")
        else:
            logging.debug(f"No JoinData found for '{join_name}'.")

        if join_metadata_match:
            join_metadata_content = join_metadata_match.group(1)
            description_match = re.search(r'Description\s*=\s*"([^"]+)"', join_metadata_content)
            if description_match:
                description = description_match.group(1)
                logging.debug(f"Description found: '{description}'")
            else:
                logging.debug(f"No description found in join metadata for '{join_name}'.")

            join_type_match = re.search(r'JoinType\s*=\s*eJoinType\.(\w+)', join_metadata_content)
            if join_type_match:
                join_type = join_type_match.group(1)
                logging.debug(f"Join type found: {join_type}")
            else:
                logging.debug(f"No join type found in join metadata for '{join_name}'.")
        else:
            logging.debug(f"No JoinMetadata found for '{join_name}'.")

        if join_name and join_number and join_type:
            logging.debug(f"Adding join '{join_name}' to join map info.")
            joinmap_info.append({
                "name": join_name,
                "join_number": join_number,
                "type": join_type,
                "description": description
            })
        else:
            logging.warning(f"Incomplete join information for '{join_name}'. Skipping.")

    return joinmap_info




def generate_markdown_chart(joins, section_title):
    logging.debug(f"Generating markdown chart for section '{section_title}'.")
    if not joins:
        logging.debug("No joins to include in the chart.")
        return ''
    markdown_chart = f'### {section_title}\n\n'

    # Group joins by type
    joins_by_type = {'Digital': [], 'Analog': [], 'Serial': []}
    for join in joins:
        if join['type'] in joins_by_type:
            joins_by_type[join['type']].append(join)
        else:
            joins_by_type['Digital'].append(join)  # Default to Digital if type not recognized

    for join_type in ['Digital', 'Analog', 'Serial']:
        if joins_by_type[join_type]:
            markdown_chart += f"#### {join_type}s\n\n"
            markdown_chart += "| Join | Type (RW) | Description |\n"
            markdown_chart += "| --- | --- | --- |\n"
            for join in joins_by_type[join_type]:
                markdown_chart += f"| {join['join_number']} | R | {join['description']} |\n"
            markdown_chart += '\n'
    logging.debug(f"Markdown chart generated for '{section_title}'.")
    return markdown_chart

def generate_config_example_markdown(sample_config):
    logging.debug("Generating config example markdown.")
    markdown = "### Config Example\n\n"
    markdown += "```json\n"
    markdown += json.dumps(sample_config, indent=4)
    markdown += "\n```\n"
    return markdown

def generate_markdown_list(items, section_title):
    logging.debug(f"Generating markdown list for section '{section_title}'.")
    if not items:
        logging.debug(f"No items to include in section '{section_title}'.")
        return ''
    markdown = f'### {section_title}\n\n'
    for item in items:
        markdown += f"- {item}\n"
    markdown += '\n'
    return markdown

def parse_all_classes(directory):
    logging.debug(f"Parsing all classes in directory: {directory}")
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
        logging.debug(f"Entering directory: {root}")
        for file in files:
            if file.endswith('.cs'):
                file_path = os.path.join(root, file)
                logging.debug(f"Processing file: {file_path}")
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    # Find all class definitions
                    for class_match in class_pattern.finditer(content):
                        class_name = class_match.group(1)
                        logging.debug(f"Class found: {class_name}")
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
                            logging.debug(f"Property found in class '{class_name}': {prop_name} ({prop_type})")
                        class_defs[class_name] = properties
    logging.debug("Finished parsing all classes.")
    return class_defs

def extract_class_body(content, start_index):
    logging.debug(f"Extracting class body starting at index {start_index}.")
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
    class_body = content[start_index:index - 1]
    logging.debug(f"Class body extracted. Length: {len(class_body)} characters.")
    return class_body, index - 1

def generate_sample_value(property_type, class_defs, processed_classes=None):
    if processed_classes is None:
        processed_classes = set()
    property_type = property_type.strip()
    # Handle nullable types
    property_type = property_type.rstrip('?')
    logging.debug(f"Generating sample value for type '{property_type}'.")
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
            logging.debug(f"Already processed class '{property_type}', avoiding recursion.")
            return {}
        logging.debug(f"Processing custom class '{property_type}'.")
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
        logging.debug(f"Unknown type '{property_type}', using default sample value.")
        return "SampleValue"

def generate_sample_config(config_class_name, class_defs, supported_types):
    logging.debug(f"Generating sample config for class '{config_class_name}'.")
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
    logging.debug(f"Sample config generated: {config}")
    return config

def read_readme_file(filepath):
    logging.debug(f"Reading README file at: {filepath}")
    if not os.path.exists(filepath):
        logging.warning(f"README.md file not found at {filepath}. A new file will be created.")
        return ""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
        logging.debug("README.md file content successfully read.")
        return content

def update_readme_section(readme_content, section_title, new_section_content):
    logging.debug(f"Updating README section '{section_title}'.")
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
            logging.info(f"Skipping section: {section_title} (found <!-- SKIP -->)")
            return readme_content  # Return the original content unchanged
        else:
            logging.debug(f"Updating existing section: {section_title}")
            updated_section = f'{start_marker}\n{new_section_content.rstrip()}\n{end_marker}'
            updated_readme = readme_content[:match.start()] + updated_section + readme_content[match.end():]
    else:
        logging.debug(f"Adding new section: {section_title}")
        # Ensure there's a newline before adding the new section
        if not readme_content.endswith('\n'):
            readme_content += '\n'
        updated_section = f'{start_marker}\n{new_section_content.rstrip()}\n{end_marker}\n'
        updated_readme = readme_content + updated_section
    return updated_readme

def remove_duplicates_preserve_order(seq):
    logging.debug("Removing duplicates while preserving order.")
    seen = set()
    unique_list = [x for x in seq if not (x in seen or seen.add(x))]
    logging.debug(f"Unique items: {unique_list}")
    return unique_list

if __name__ == "__main__":
    project_directory = os.path.abspath("./")
    logging.info(f"Starting processing in project directory: {project_directory}")
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
        logging.warning("No config classes found.")
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
        logging.info("README.md has been updated.")

    logging.info("Processing completed.")