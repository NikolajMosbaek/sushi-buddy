"""Joins the rendered frames (transparent PNGs, frame-<seconds>s.png) into the README's GIF."""

import glob
import os
import re
import sys

from PIL import Image

frames_dir, out, fps = sys.argv[1], sys.argv[2], int(sys.argv[3])
BACKGROUND = (246, 241, 232)  # warm paper: reads on GitHub's light and dark themes

paths = sorted(
    glob.glob(os.path.join(frames_dir, 'frame-*s.png')),
    key=lambda path: float(re.search(r'frame-([\d.]+)s\.png$', path).group(1)),
)
layers = [Image.open(path).convert('RGBA') for path in paths]

# Crop to the band the flight uses, top to bottom, with a margin.
MARGIN = 28
boxes = [box for box in (layer.getchannel('A').getbbox() for layer in layers) if box]
top = max(0, min(box[1] for box in boxes) - MARGIN)
bottom = min(layers[0].height, max(box[3] for box in boxes) + MARGIN)

frames = []
for layer in layers:
    frame = Image.new('RGBA', layer.size, BACKGROUND + (255,))
    frame.alpha_composite(layer)
    frames.append(frame.crop((0, top, layer.width, bottom)).convert('RGB'))

# One palette for every frame, so colours do not flicker between frames.
sample = Image.new('RGB', (frames[0].width, frames[0].height * 4))
for row, index in enumerate(range(0, len(frames), max(1, len(frames) // 4))):
    if row < 4:
        sample.paste(frames[index], (0, frames[0].height * row))
palette = sample.quantize(colors=128, method=Image.Quantize.MEDIANCUT)
gif = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]

gif[0].save(out, save_all=True, append_images=gif[1:], duration=1000 // fps, loop=0, optimize=True)
