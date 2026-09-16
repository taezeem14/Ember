import os
import math
from PIL import Image, ImageDraw, ImageFilter

S = 1024
base = Image.new("RGBA", (S, S), (18, 18, 18, 255))

# 1. Subtle radial ambient glow behind the badge
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
g_draw = ImageDraw.Draw(glow)
cx, cy = S // 2, S // 2

for r, a, c in [
    (460, 30, (13, 71, 161)),    # Deep sapphire
    (380, 50, (30, 136, 229)),   # Azure
    (300, 80, (41, 121, 255)),   # Electric Blue
    (200, 120, (0, 212, 255)),   # Cyan
]:
    g_draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*c, a))

glow = glow.filter(ImageFilter.GaussianBlur(radius=40))
base = Image.alpha_composite(base, glow)

# 2. Main Spotify-style Electric Blue Circle
circle_radius = 360
circle_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
c_draw = ImageDraw.Draw(circle_layer)

# Draw radial gradient circle
for r in range(circle_radius, 0, -2):
    t = r / circle_radius
    # Interp from outer Electric Cobalt (41, 121, 255) to inner Electric Cyan (0, 229, 255)
    cr = int(41 * (1 - t) + 0 * t)
    cg = int(121 * (1 - t) + 212 * t)
    cb = int(255)
    c_draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(cr, cg, cb, 255))

# Subtle outer ring
c_draw.ellipse([cx - circle_radius, cy - circle_radius, cx + circle_radius, cy + circle_radius], outline=(0, 229, 255, 180), width=6)
base = Image.alpha_composite(base, circle_layer)

# 3. Draw 3 Spotify sound waves (curved arcs)
# In Spotify, 3 curved lines tilted slightly (~ -15 to -20 degrees), thicker in center and tapered at ends
wave_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
w_draw = ImageDraw.Draw(wave_layer)

# Wave parameters: center (cx, cy + offset), radius, start_angle, end_angle, width
# Tilted arcs roughly from 195 deg to 345 deg
waves = [
    {"r": 230, "w": 46, "dy": 40, "start": 200, "end": 340},
    {"r": 160, "w": 40, "dy": 25, "start": 195, "end": 345},
    {"r": 90,  "w": 34, "dy": 10, "start": 190, "end": 350},
]

for wave in waves:
    r = wave["r"]
    w = wave["w"]
    w_cy = cy + wave["dy"]
    # Draw arc with pure white
    w_draw.arc(
        [cx - r, w_cy - r, cx + r, w_cy + r],
        start=wave["start"],
        end=wave["end"],
        fill=(18, 18, 18, 255),
        width=w
    )

base = Image.alpha_composite(base, wave_layer)

# 4. Refined squircle border
margin = 44
radius = 210
border_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
b_draw = ImageDraw.Draw(border_layer)
b_draw.rounded_rectangle([margin, margin, S - margin, S - margin], 
                          radius=radius, outline=(41, 121, 255, 100), width=10)
b_draw.rounded_rectangle([margin + 6, margin + 6, S - margin - 6, S - margin - 6], 
                          radius=radius - 6, outline=(0, 212, 255, 40), width=3)
base = Image.alpha_composite(base, border_layer)

# 5. Apply rounded squircle mask
squircle_mask = Image.new("L", (S, S), 0)
sq_draw = ImageDraw.Draw(squircle_mask)
sq_draw.rounded_rectangle([margin, margin, S - margin, S - margin], radius=radius, fill=255)

final_icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
final_icon.paste(base, (0, 0), squircle_mask)

# Save to Android mipmaps
res_dir = r"d:\download-chrome\Ember\ember_mobile\android\app\src\main\res"
targets = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

for folder, sz in targets.items():
    out_dir = os.path.join(res_dir, folder)
    os.makedirs(out_dir, exist_ok=True)
    out_file = os.path.join(out_dir, "ic_launcher.png")
    resized = final_icon.resize((sz, sz), Image.Resampling.LANCZOS)
    resized.save(out_file, "PNG", optimize=True)
    print(f"Saved {out_file} ({sz}x{sz})")

artifact_dir = r"C:\Users\Matta\.gemini\antigravity\brain\318dab8b-7475-4f37-9a03-38261142b5b7"
art_preview = os.path.join(artifact_dir, "spotify_blue_app_icon.png")
p512 = final_icon.resize((512, 512), Image.Resampling.LANCZOS)
p512.save(art_preview, "PNG", optimize=True)
print(f"Preview saved to {art_preview}")
