#!/usr/bin/env python3
"""Generate the fictional, vector-only release-demo PDF (requires reportlab)."""
from pathlib import Path
import math
import subprocess
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

root = Path(__file__).resolve().parents[1]
out = root/'output/pdf'
out.mkdir(parents=True, exist_ok=True)
path = out/'A slower weekend.pdf'
fonts = {'Helvetica': 'Noto Sans:style=Regular', 'Helvetica-Bold': 'Noto Sans:style=Bold',
         'Helvetica-Oblique': 'Noto Sans:style=Italic', 'Times-Roman': 'Noto Serif:style=Regular',
         'Times-Italic': 'Noto Serif:style=Italic'}
for name, family in fonts.items():
    file = subprocess.check_output(['fc-match', family, '-f', '%{file}'], text=True)
    pdfmetrics.registerFont(TTFont('Demo'+name, file))
c = canvas.Canvas(str(path), pagesize=(600, 760), pageCompression=1)
c.setTitle('A slower weekend - fictional demo')
c.setAuthor('Oma Preview')
paper, ink, quiet, line, green = '#F7F5EF', '#253D36', '#72796E', '#D5D9CC', '#DCE5D4'
def text(x, top, value, size=12, font='Helvetica', color=ink):
    c.setFillColor(HexColor(color)); c.setFont('Demo'+font, size)
    c.drawString(x, 760-top, value)
def rule(top, x=52, end=548):
    c.setStrokeColor(HexColor(line)); c.setLineWidth(.7)
    c.line(x, 760-top, end, 760-top)
def base(n, section):
    c.setFillColor(HexColor(paper)); c.rect(0,0,600,760,fill=1,stroke=0)
    text(52, 44, 'FIELDWORK', 10, 'Helvetica-Bold')
    text(365,44,'THE WEEKEND EDITION  /  01',9,color=quiet)
    rule(62); rule(708)
    text(52,730,'Fictional sample. Real possibilities.',9,color=quiet)
    text(442,730,f'{section}   /   0{n}',9,color=quiet)

base(1,'READ')
text(52,148,'A slower',60,'Times-Roman')
text(52,209,'weekend.',60,'Times-Italic')
text(54,252,'Less planning. More looking around.',14)
text(54,279,'Three pages for a little time away.',11,color=quiet)
c.setFillColor(HexColor(green)); c.roundRect(52,94,496,330,12,fill=1,stroke=0)
# Flowing contour lines: an original vector illustration, not a stock photo.
c.saveState(); clip=c.beginPath(); clip.rect(52,94,496,330); c.clipPath(clip,stroke=0)
for j in range(19):
    p=c.beginPath()
    for i in range(151):
        x=25+i*4; y=110+j*18+34*math.sin(i*.038+j*.09)+22*math.sin(i*.067+.5)
        if i==0:p.moveTo(x,y)
        else:p.lineTo(x,y)
    c.setStrokeColor(HexColor('#82957A')); c.setLineWidth(.7); c.drawPath(p)
c.restoreState()
c.setFillColor(HexColor('#F0CE8C')); c.circle(450,356,34,fill=1,stroke=0)
text(72,624,'OUT OF OFFICE.',10,'Helvetica-Bold')
text(72,644,'IN THE MOMENT.',10,'Helvetica-Bold')
text(54,689,'01  A little inspiration     02  Room to wander     03  Make it yours',9,color=quiet)
c.showPage()

base(2,'WANDER')
text(52,140,'Room to wander.',41,'Times-Roman')
text(54,178,'An itinerary with plenty of space between the lines.',12,color=quiet)
for top, day, title, lines in [
    (244,'FRIDAY','Arrive without a rush.', ['Leave the city behind. Find your room, open the window,', 'and take the long way to dinner. Nothing else is booked.']),
    (384,'SATURDAY','Follow your curiosity.', ['Coffee first. Then the riverside path, the little bookshop,', 'and whichever turn looks interesting. Bring a notebook.']),
    (524,'SUNDAY','Keep the morning free.', ['Sunday is for a late breakfast and one more walk.', 'Head home with a story, not a checklist.'])]:
    text(54,top,day,9,'Helvetica-Bold',quiet)
    text(54,top+35,title,24,'Times-Roman')
    for k,s in enumerate(lines):text(54,top+63+k*19,s,11)
    rule(top+106)
text(54,680,'THE ONLY RULE: leave a little room for the unexpected.',10,'Helvetica-Oblique')
c.showPage()

base(3,'MAKE IT YOURS')
text(52,137,'Make it yours.',43,'Times-Roman')
text(54,175,'A few details. The rest can wait.',12,color=quiet)
for top, label in [(235,'YOUR NAME'),(360,'A NOTE FOR THE HOST')]:
    text(54,top,label,9,'Helvetica-Bold',quiet)
    rule(top+54)
    if top==360:rule(top+87)
c.setFillColor(HexColor(green)); c.roundRect(52,160,496,105,8,fill=1,stroke=0)
text(72,523,'Small details make a stay.',23,'Times-Roman')
text(72,552,'A favourite tea. A quiet room. Somewhere to leave your bike.',11)
text(72,573,'Tell us what would make this weekend feel like yours.',11)
text(54,665,'No form fields needed. Just put your words on the page.',10,color=quiet)
c.showPage(); c.save()
print(path)
