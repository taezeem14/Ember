import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

font_path = r"C:\Users\Matta\AppData\Local\Pub\Cache\hosted\pub.dev\font_awesome_flutter-11.0.0\lib\fonts\Font-Awesome-7-Free-Solid-900.otf"
glyph = chr(0xf06d) # FontAwesome Solid Fire

S = 1024
base = Image.new("RGBA", (S, S), (11, 9, 7, 255))

# 1. Radial ambient warmth behind the flame
glow_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
g_draw = ImageDraw.Draw(glow_layer)
cx, cy = S // 2, S // 2 + 10

for r, a, c in [
    (420, 35, (180, 83, 9)),
    (320, 65, (217, 119, 6)),
    (220, 115, (245, 158, 11)),
    (140, 160, (251, 191, 36)),
]:
    g_draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*c, a))

glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(radius=42))
base = Image.alpha_composite(base, glow_layer)

# 2. Flame glyph rendering
font_size = 560
font = ImageFont.truetype(font_path, font_size)

dummy = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d_dummy = ImageDraw.Draw(dummy)
bbox = d_dummy.textbbox((0, 0), glyph, font=font)
gw = bbox[2] - bbox[0]
gh = bbox[3] - bbox[1]
gx = (S - gw) // 2 - bbox[0]
gy = (S - gh) // 2 - bbox[1]

# Warm bloom layer
bloom_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
b_draw = ImageDraw.Draw(bloom_layer)
b_draw.text((gx, gy), glyph, font=font, fill=(245, 158, 11, 240))
bloom_layer = bloom_layer.filter(ImageFilter.GaussianBlur(radius=30))
base = Image.alpha_composite(base, bloom_layer)

# High-resolution flame mask
flame_mask = Image.new("L", (S, S), 0)
f_draw = ImageDraw.Draw(flame_mask)
f_draw.text((gx, gy), glyph, font=font, fill=255)

# Rich fiery vertical gradient
grad_img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
g_grad = ImageDraw.Draw(grad_img)

top_y = gy + bbox[1]
bot_y = gy + bbox[3]
span = max(1, bot_y - top_y)

for y in range(max(0, top_y - 20), min(S, bot_y + 30)):
    t = max(0.0, min(1.0, (y - top_y) / span))
    # Top tips: luminous cream gold (255, 250, 200)
    # 20%: bright amber gold (251, 191, 36)
    # 55%: rich fiery orange (245, 120, 15)
    # Base: deep ember red (215, 45, 18)
    if t < 0.20:
        u = t / 0.20
        r = int(255 * (1 - u) + 251 * u)
        g = int(250 * (1 - u) + 191 * u)
        b = int(200 * (1 - u) + 36 * u)
    elif t < 0.58:
        u = (t - 0.20) / 0.38
        r = int(251 * (1 - u) + 245 * u)
        g = int(191 * (1 - u) + 120 * u)
        b = int(36 * (1 - u) + 15 * u)
    else:
        u = (t - 0.58) / 0.42
        r = int(245 * (1 - u) + 215 * u)
        g = int(120 * (1 - u) + 45 * u)
        b = int(15 * (1 - u) + 18 * u)
    g_grad.line([(0, y), (S, y)], fill=(r, g, b, 255))

flame_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
flame_layer.paste(grad_img, (0, 0), flame_mask)

# Internal radial hearth luminescence
hearth = Image.new("RGBA", (S, S), (0, 0, 0, 0))
h_draw = ImageDraw.Draw(hearth)
hcx, hcy = cx, top_y + int(span * 0.58)
for hr, ha in [(160, 40), (110, 80), (60, 140)]:
    h_draw.ellipse([hcx - hr, hcy - hr, hcx + hr, hcy + hr], fill=(255, 245, 200, ha))
hearth = hearth.filter(ImageFilter.GaussianBlur(radius=20))

flame_final = Image.new("RGBA", (S, S), (0, 0, 0, 0))
flame_final.paste(flame_layer, (0, 0))
flame_final = Image.alpha_composite(flame_final, hearth)

# Re-apply flame mask so hearth doesn't leak outside flame
base_flame = Image.new("RGBA", (S, S), (0, 0, 0, 0))
base_flame.paste(flame_final, (0, 0), flame_mask)
base = Image.alpha_composite(base, base_flame)

# Refined squircle border
margin = 44
radius = 210
border_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
b_draw2 = ImageDraw.Draw(border_layer)
b_draw2.rounded_rectangle([margin, margin, S - margin, S - margin], 
                          radius=radius, outline=(245, 158, 11, 80), width=10)
b_draw2.rounded_rectangle([margin + 6, margin + 6, S - margin - 6, S - margin - 6], 
                          radius=radius - 6, outline=(255, 255, 255, 20), width=3)
base = Image.alpha_composite(base, border_layer)

# Apply rounded squircle mask
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

artifact_dir = r"C:\Users\Matta\.gemini\antigravity\brain\318dab8b-7475-4f37-9a03-38261142b5b7"
art_preview = os.path.join(artifact_dir, "ember_app_icon.png")
p512 = final_icon.resize((512, 512), Image.Resampling.LANCZOS)
p512.save(art_preview, "PNG", optimize=True)
print("Updated refined icon saved!")
