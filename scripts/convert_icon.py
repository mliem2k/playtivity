#!/usr/bin/env python3
"""
Playtivity Icon & Image Converter
Converts SVG/PNG/JPG to PNG files and creates:
- Android mipmap icons (replaces existing ones)
- Flutter app images for different use cases

Usage: python convert_icon.py <image_file_path>
Examples: 
  python convert_icon.py spotify_icon_template.svg
  python convert_icon.py my_icon.png
  python convert_icon.py logo.jpg
"""

import sys
import os
from PIL import Image
from pathlib import Path

# Import cairosvg only when needed (for SVG files)
cairosvg = None

def detect_file_format(file_path):
    """Detect the format of the input file"""
    file_ext = Path(file_path).suffix.lower()
    
    if file_ext == '.svg':
        return 'svg'
    elif file_ext in ['.png', '.jpg', '.jpeg', '.bmp', '.tiff', '.webp']:
        return 'raster'
    else:
        # Try to detect by content
        try:
            with open(file_path, 'rb') as f:
                header = f.read(10)
                if header.startswith(b'<svg') or b'<svg' in header:
                    return 'svg'
                elif header.startswith(b'\x89PNG'):
                    return 'raster'
                elif header.startswith(b'\xff\xd8\xff'):
                    return 'raster'
                else:
                    return 'unknown'
        except:
            return 'unknown'

def convert_image_to_png_sizes(image_path, output_dir="temp_icons"):
    """Convert image (SVG/PNG/JPG) to multiple PNG sizes for Android"""
    
    # Android icon sizes (density -> size in pixels)
    sizes = {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192
    }
    
    # Create temp directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Detect file format
    file_format = detect_file_format(image_path)
    print(f"Detected format: {file_format.upper()}")
    print(f"Converting {image_path} to PNG files...")
    
    png_files = {}
    
    for density, size in sizes.items():
        output_path = os.path.join(output_dir, f"ic_launcher_{density}.png")
        
        if file_format == 'svg':
            # Try to import and use cairosvg, fallback to alternative methods
            global cairosvg
            if cairosvg is None:
                try:
                    import cairosvg
                except ImportError:
                    print("⚠️  cairosvg not available, trying alternative SVG conversion...")
                    # Try alternative SVG conversion using PIL and svg2rlg
                    try:
                        from reportlab.graphics import renderPM
                        from svglib.svglib import renderSVG
                        drawing = renderSVG.renderSVG(image_path)
                        renderPM.drawToFile(drawing, output_path, fmt='PNG', 
                                          dpi=72, bg=0xffffff)
                        continue
                    except ImportError:
                        # Final fallback: suggest manual conversion
                        raise ImportError(
                            "SVG conversion requires additional libraries.\n"
                            "Options:\n"
                            "1. Install cairosvg with system dependencies:\n"
                            "   - Download GTK3 runtime from https://github.com/tschoonj/GTK-for-Windows-Runtime-Environment-Installer\n"
                            "   - Then: pip install cairosvg\n"
                            "2. Or install alternative: pip install reportlab svglib\n"
                            "3. Or manually convert your SVG to PNG using online tools"
                        )
            
            try:
                # Convert SVG to PNG with specific size
                cairosvg.svg2png(
                    url=image_path,
                    write_to=output_path,
                    output_width=size,
                    output_height=size
                )
            except Exception as e:
                if "cairo" in str(e).lower():
                    raise ImportError(
                        f"Cairo library error: {e}\n\n"
                        "To fix this on Windows:\n"
                        "1. Download and install GTK3 runtime:\n"
                        "   https://github.com/tschoonj/GTK-for-Windows-Runtime-Environment-Installer\n"
                        "2. Restart your terminal/IDE\n"
                        "3. Try again\n\n"
                        "Alternative: Convert your SVG to PNG manually and use the PNG version instead."
                    )
                else:
                    raise e
        elif file_format == 'raster':
            # Convert raster image (PNG/JPG/etc) to PNG with specific size
            with Image.open(image_path) as img:
                # Convert to RGBA if not already (handles transparency)
                if img.mode != 'RGBA':
                    img = img.convert('RGBA')
                
                # Resize image maintaining aspect ratio
                img_resized = img.resize((size, size), Image.Resampling.LANCZOS)
                
                # Save as PNG
                img_resized.save(output_path, 'PNG')
        else:
            raise ValueError(f"Unsupported file format: {file_format}")
        
        png_files[density] = output_path
        print(f"✓ Created {density} ({size}x{size}): {output_path}")
    
    return png_files

def create_flutter_app_images(image_path):
    """Create Flutter app images for different use cases"""
    
    # Flutter app image sizes
    flutter_sizes = {
        'playtivity_logo.png': (120, 120),
        'playtivity_logo_login_screen.png': (120, 120),
        'playtivity_logo_button_icon.png': (24, 24),
        'playtivity_logo_large_display.png': (200, 200),
        'playtivity_logo_small_icon.png': (48, 48)
    }
    
    # Create assets/images directory if it doesn't exist
    assets_dir = "assets/images"
    os.makedirs(assets_dir, exist_ok=True)
    
    # Detect file format
    file_format = detect_file_format(image_path)
    print(f"\nCreating Flutter app images...")
    
    flutter_files = {}
    
    for filename, size in flutter_sizes.items():
        output_path = os.path.join(assets_dir, filename)
        
        if file_format == 'svg':
            # Try to import and use cairosvg, fallback to alternative methods
            global cairosvg
            if cairosvg is None:
                try:
                    import cairosvg
                except ImportError:
                    print("⚠️  cairosvg not available, trying alternative SVG conversion...")
                    # Try alternative SVG conversion using PIL and svg2rlg
                    try:
                        from reportlab.graphics import renderPM
                        from svglib.svglib import renderSVG
                        drawing = renderSVG.renderSVG(image_path)
                        renderPM.drawToFile(drawing, output_path, fmt='PNG', 
                                          dpi=72, bg=0xffffff)
                        continue
                    except ImportError:
                        # Final fallback: suggest manual conversion
                        raise ImportError(
                            "SVG conversion requires additional libraries.\n"
                            "Options:\n"
                            "1. Install cairosvg with system dependencies:\n"
                            "   - Download GTK3 runtime from https://github.com/tschoonj/GTK-for-Windows-Runtime-Environment-Installer\n"
                            "   - Then: pip install cairosvg\n"
                            "2. Or install alternative: pip install reportlab svglib\n"
                            "3. Or manually convert your SVG to PNG using online tools"
                        )
            
            try:
                # Convert SVG to PNG with specific size
                cairosvg.svg2png(
                    url=image_path,
                    write_to=output_path,
                    output_width=size[0],
                    output_height=size[1]
                )
            except Exception as e:
                if "cairo" in str(e).lower():
                    raise ImportError(
                        f"Cairo library error: {e}\n\n"
                        "To fix this on Windows:\n"
                        "1. Download and install GTK3 runtime:\n"
                        "   https://github.com/tschoonj/GTK-for-Windows-Runtime-Environment-Installer\n"
                        "2. Restart your terminal/IDE\n"
                        "3. Try again\n\n"
                        "Alternative: Convert your SVG to PNG manually and use the PNG version instead."
                    )
                else:
                    raise e
        elif file_format == 'raster':
            # Convert raster image (PNG/JPG/etc) to PNG with specific size
            with Image.open(image_path) as img:
                # Convert to RGBA if not already (handles transparency)
                if img.mode != 'RGBA':
                    img = img.convert('RGBA')
                
                # Resize image maintaining aspect ratio
                img_resized = img.resize(size, Image.Resampling.LANCZOS)
                
                # Save as PNG
                img_resized.save(output_path, 'PNG')
        else:
            raise ValueError(f"Unsupported file format: {file_format}")
        
        flutter_files[filename] = output_path
        print(f"✓ Created {filename} ({size[0]}x{size[1]}): {output_path}")
    
    return flutter_files

def replace_android_icons(png_files):
    """Replace Android mipmap icons with new PNG files"""
    
    android_res_path = "android/app/src/main/res"
    
    if not os.path.exists(android_res_path):
        print(f"❌ Error: Android resources directory not found: {android_res_path}")
        print("Make sure you're running this script from the Flutter project root.")
        return False
    
    print(f"\nReplacing Android mipmap icons...")
    
    for density, png_file in png_files.items():
        mipmap_dir = os.path.join(android_res_path, f"mipmap-{density}")
        target_file = os.path.join(mipmap_dir, "ic_launcher.png")
        
        # Create mipmap directory if it doesn't exist
        os.makedirs(mipmap_dir, exist_ok=True)
        
        # Copy PNG file to mipmap directory
        try:
            import shutil
            shutil.copy2(png_file, target_file)
            print(f"✓ Replaced {target_file}")
        except Exception as e:
            print(f"❌ Error replacing {target_file}: {e}")
            return False
    
    return True

def cleanup_temp_files(output_dir="temp_icons"):
    """Clean up temporary PNG files"""
    try:
        import shutil
        if os.path.exists(output_dir):
            shutil.rmtree(output_dir)
            print(f"\n🧹 Cleaned up temporary files in {output_dir}")
    except Exception as e:
        print(f"⚠️  Warning: Could not clean up temp files: {e}")

def main():
    if len(sys.argv) != 2:
        print("Usage: python convert_icon.py <image_file_path>")
        print("Examples:")
        print("  python convert_icon.py spotify_icon_template.svg")
        print("  python convert_icon.py my_icon.png")
        print("  python convert_icon.py logo.jpg")
        print("\nSupported formats: SVG, PNG, JPG, JPEG, BMP, TIFF, WEBP")
        sys.exit(1)
    
    image_path = sys.argv[1]
    
    # Check if image file exists
    if not os.path.exists(image_path):
        print(f"❌ Error: Image file not found: {image_path}")
        sys.exit(1)
    
    print("🎨 Playtivity Icon & Image Converter")
    print("=" * 45)
    
    try:
        # Detect and validate file format
        file_format = detect_file_format(image_path)
        if file_format == 'unknown':
            print(f"❌ Error: Unsupported file format for: {image_path}")
            print("Supported formats: SVG, PNG, JPG, JPEG, BMP, TIFF, WEBP")
            sys.exit(1)
        
        # Convert image to PNG files
        png_files = convert_image_to_png_sizes(image_path)
        
        # Create Flutter app images
        flutter_files = create_flutter_app_images(image_path)
        
        # Replace Android icons
        android_success = replace_android_icons(png_files)
        
        if android_success:
            print("\n✅ Successfully updated all Android mipmap icons!")
        else:
            print("\n❌ Failed to replace some Android icons")
        
        print("\n✅ Successfully created all Flutter app images!")
        print("\nFiles created:")
        print("📱 Android Icons:")
        for density, png_file in png_files.items():
            size = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}[density]
            print(f"   - mipmap-{density}/ic_launcher.png ({size}x{size})")
        
        print("\n🖼️  Flutter App Images:")
        print("   - assets/images/playtivity_logo.png (120x120) - Main login screen")
        print("   - assets/images/playtivity_logo_login_screen.png (120x120)")
        print("   - assets/images/playtivity_logo_button_icon.png (24x24)")
        print("   - assets/images/playtivity_logo_large_display.png (200x200)")
        print("   - assets/images/playtivity_logo_small_icon.png (48x48)")
        
        print("\n🚀 Next steps:")
        print("1. Run: flutter clean")
        print("2. Run: flutter build apk")
        print("3. Install the APK to see your new icon")
        print("4. Run: flutter run to see the updated app images")
        
        if not android_success:
            sys.exit(1)
            
    except ImportError as e:
        print(f"\n❌ Missing required Python packages:")
        missing_packages = []
        if "cairosvg" in str(e):
            missing_packages.append("cairosvg")
        if "PIL" in str(e):
            missing_packages.append("Pillow")
        
        if missing_packages:
            print(f"Install with: pip install {' '.join(missing_packages)}")
        else:
            print("Install with: pip install cairosvg Pillow")
        
        print("\nNote: cairosvg is only needed for SVG files")
        print("For PNG/JPG files, you only need: pip install Pillow")
        sys.exit(1)
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        sys.exit(1)
    
    finally:
        # Clean up temporary files
        cleanup_temp_files()

if __name__ == "__main__":
    main() 