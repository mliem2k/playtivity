# Playtivity Scripts

This folder contains utility scripts for the Playtivity project.

## 🎨 Icon & Image Converter (`convert_icon.py`)

A comprehensive script that converts SVG/PNG/JPG images into all the required formats for the Playtivity Flutter app.

### What it generates:

**📱 Android Icons:**
- `mipmap-mdpi/ic_launcher.png` (48x48)
- `mipmap-hdpi/ic_launcher.png` (72x72)
- `mipmap-xhdpi/ic_launcher.png` (96x96)
- `mipmap-xxhdpi/ic_launcher.png` (144x144)
- `mipmap-xxxhdpi/ic_launcher.png` (192x192)

**🖼️ Flutter App Images:**
- `assets/images/playtivity_logo.png` (120x120) - Main login screen
- `assets/images/playtivity_logo_login_screen.png` (120x120)
- `assets/images/playtivity_logo_button_icon.png` (24x24)
- `assets/images/playtivity_logo_large_display.png` (200x200)
- `assets/images/playtivity_logo_small_icon.png` (48x48)

### Prerequisites

1. **Install Python dependencies:**
   ```bash
   cd scripts
   pip install -r requirements.txt
   ```

2. **For SVG files on Windows (if needed):**
   - Download and install [GTK3 Runtime](https://github.com/tschoonj/GTK-for-Windows-Runtime-Environment-Installer)
   - Restart your terminal/IDE after installation

### Usage

1. **Navigate to the project root** (not the scripts folder):
   ```bash
   cd /path/to/playtivity
   ```

2. **Run the script with your image:**
   ```bash
   python scripts/convert_icon.py your_image.svg
   python scripts/convert_icon.py your_image.png
   python scripts/convert_icon.py your_image.jpg
   ```

### Supported Formats

- **SVG** - Vector graphics (recommended for best quality)
- **PNG** - Portable Network Graphics
- **JPG/JPEG** - JPEG images
- **BMP** - Bitmap images
- **TIFF** - Tagged Image File Format
- **WEBP** - WebP images

### Example Usage

```bash
# Using an SVG file (recommended)
python scripts/convert_icon.py assets/logo.svg

# Using a PNG file
python scripts/convert_icon.py assets/logo.png

# Using a JPG file
python scripts/convert_icon.py assets/logo.jpg
```

### After Running the Script

1. **Clean and rebuild:**
   ```bash
   flutter clean
   flutter pub get
   ```

2. **Test the app:**
   ```bash
   flutter run
   ```

3. **Build APK to see new icon:**
   ```bash
   flutter build apk
   ```

### Troubleshooting

**SVG Conversion Issues:**
- Install GTK3 Runtime for Windows
- Alternative: Use PNG/JPG instead of SVG
- Alternative: Install fallback libraries: `pip install reportlab svglib`

**Permission Errors:**
- Run terminal as administrator (Windows)
- Check file permissions

**File Not Found:**
- Make sure you're running from the project root directory
- Check that your image file path is correct

### Technical Details

The script automatically:
- Detects input file format (SVG, PNG, JPG, etc.)
- Creates temporary files during processing
- Replaces existing Android mipmap icons
- Creates Flutter app images in the assets folder
- Cleans up temporary files after completion
- Provides detailed feedback about created files

Perfect for maintaining consistent branding across your Flutter app and Android icons!