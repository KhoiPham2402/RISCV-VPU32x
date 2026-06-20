import os
import shutil

def convert_sv_to_txt(directory='.'):
    """
    Convert all .sv files to .txt files in the specified directory.
    Overwrites existing .txt files with the content from .sv files.
    
    Args:
        directory: The directory to search for .sv files (default: current directory)
    """
    # Get all .sv files in the directory
    sv_files = [f for f in os.listdir(directory) if f.endswith('.sv')]
    
    if not sv_files:
        print("No .sv files found in the directory.")
        return
    
    print(f"Found {len(sv_files)} .sv file(s) to convert:")
    
    converted_count = 0
    updated_count = 0
    
    for sv_file in sv_files:
        # Create the new filename with .txt extension
        txt_file = sv_file[:-3] + '.txt'
        
        # Full paths
        src_path = os.path.join(directory, sv_file)
        dst_path = os.path.join(directory, txt_file)
        
        try:
            # Check if txt file already exists
            file_exists = os.path.exists(dst_path)
            
            # Copy/overwrite the file with new extension
            shutil.copy2(src_path, dst_path)
            
            if file_exists:
                print(f"✓ Updated: {sv_file} -> {txt_file} (overwritten)")
                updated_count += 1
            else:
                print(f"✓ Created: {sv_file} -> {txt_file}")
            converted_count += 1
        except Exception as e:
            print(f"✗ Error converting {sv_file}: {e}")
    
    print(f"\nConversion complete! {converted_count} file(s) processed ({updated_count} updated, {converted_count - updated_count} created).")

if __name__ == "__main__":
    # Run the conversion in the current directory
    convert_sv_to_txt()
