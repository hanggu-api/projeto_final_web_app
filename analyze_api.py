import re

with open('/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/api_service.dart', 'r') as f:
    lines = f.readlines()

methods = []
current_method = None
brace_count = 0

for i, line in enumerate(lines):
    # Match method signatures (simplified)
    # e.g., Future<void> doSomething(String id) async {
    match = re.search(r'^\s*(?:static\s+)?(?:Future(?:<[^>]+>)?|void|Map|List|String|bool|int|dynamic|Stream(?:<[^>]+>)?)\s+([a-zA-Z0-9_]+)\s*\(', line)
    
    if match and brace_count == 1: # Assuming class starts at brace_count=1
        if current_method:
            current_method['end'] = i
            methods.append(current_method)
        current_method = {'name': match.group(1), 'start': i+1, 'end': -1, 'lines': 0}
        
    brace_count += line.count('{')
    brace_count -= line.count('}')
    
    if current_method and brace_count == 1 and line.strip() == '}':
        current_method['end'] = i+1
        methods.append(current_method)
        current_method = None

for m in methods:
    m['lines'] = m['end'] - m['start'] + 1

# Filter out small getters or non-methods if any
methods = [m for m in methods if m['lines'] > 0]

print(f"Total methods found: {len(methods)}")
methods_sorted = sorted(methods, key=lambda x: x['name'])
for m in methods_sorted:
    print(f"- {m['name']} (Lines: {m['start']} to {m['end']}, Total: {m['lines']} lines)")

