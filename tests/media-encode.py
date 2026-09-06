#!/usr/bin/env python3
"""Frame the real UI capture; add restrained chapter captions and an inline GIF."""
from pathlib import Path
import subprocess
import sys

folder=Path(sys.argv[1]).resolve(strict=True)
def font(family):
    return subprocess.check_output(['fc-match',family,'-f','%{file}'],text=True)
body=font('Noto Sans:style=Regular')
serif=font('Noto Serif:style=Regular')
chapters=[(0,3.8,'Read at your own pace.','01 / READ'),
          (3.8,7.5,'Find the bit you came for.','02 / FIND'),
          (7.5,15.3,'Your words. Anywhere on the page.','03 / FILL'),
          (15.3,19,'Make a correction. Change your mind.','04 / REFINE'),
          (19,25,'Your desktop. Your colours.','05 / BELONG'),
          (25,26.5,'Just enough tools.','06 / EDIT'),
          (26.5,30,'Save a new PDF. Keep the original.','07 / KEEP')]
filters=['pad=1360:1040:40:80:color=0x101614',
         f"drawtext=fontfile='{serif}':text='Oma Preview':x=40:y=23:fontsize=28:fontcolor=0xf7f5ef",
         f"drawtext=fontfile='{body}':text='0.9   /   A LITTLE ROOM TO WORK':x=w-tw-42:y=36:fontsize=11:fontcolor=0xaeb9b0"]
for start,end,caption,label in chapters:
    filters += [f"drawtext=fontfile='{serif}':text='{caption}':x=42:y=966:fontsize=25:fontcolor=0xf7f5ef:enable='gte(t,{start})*lt(t,{end})'",
                f"drawtext=fontfile='{body}':text='{label}':x=w-tw-42:y=977:fontsize=11:fontcolor=0xaeb9b0:enable='gte(t,{start})*lt(t,{end})'"]
filters += ['fade=t=in:st=0:d=0.25','fade=t=out:st=29.35:d=0.4','format=yuv420p']
video=folder/'oma-preview-0.9-demo.mp4'
subprocess.run(['ffmpeg','-hide_banner','-loglevel','warning','-n','-framerate','20','-i',str(folder/'frames/%05d.png'),
                '-vf',','.join(filters),'-c:v','libx264','-preset','slow','-crf','18','-movflags','+faststart',str(video)],check=True)
gif=folder/'oma-preview-0.9-demo.gif'
subprocess.run(['ffmpeg','-hide_banner','-loglevel','warning','-n','-i',str(video),'-filter_complex',
                'fps=12,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle',
                '-loop','0',str(gif)],check=True)
for p in (video,gif):print(f'{p} ({p.stat().st_size/1024/1024:.2f} MiB)')
