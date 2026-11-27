import pikepdf, math, zlib, base64, io, random
from pikepdf import Name, Dictionary, Array
from PIL import Image, ImageDraw, ImageFont
pdf=pikepdf.new(); W,H=595,842
font=pdf.make_indirect(Dictionary(Type=Name.Font,Subtype=Name.Type1,BaseFont=Name.Helvetica,Encoding=Name.WinAnsiEncoding))
gsH=pdf.make_indirect(Dictionary(Type=Name.ExtGState,CA=0.35,ca=0.35))
def testo(righe):
    s="BT /F1 13 Tf 0 0 0 rg\n"; y=780
    for r in righe: s+="1 0 0 1 60 %d Tm (%s) Tj\n"%(y,r); y-=20
    return s+"ET\n"
def marca(t): return "BT /F1 1 Tf 3 Tr 1 0 0 1 2 2 Tm (%s) Tj ET\n"%t
# ---- STILOGRAFICA: centro + spessore variabile con la direzione
def stilo(x0,y0,parola_scale=1.0):
    pts=[]
    for i in range(241):
        t=i/240*4*math.pi
        x=x0+i*1.6; y=y0+28*math.sin(t)*math.cos(t/3)+10*math.sin(3*t)
        pts.append((x,y))
    out=[]
    for i,(x,y) in enumerate(pts):
        a=pts[min(i+1,len(pts)-1)]; b=pts[max(i-1,0)]
        ang=math.atan2(a[1]-b[1],a[0]-b[0])
        w=0.6+3.2*abs(math.sin(ang-math.radians(45)))   # pennino a 45 gradi
        out.append((round(x,2),round(y,2),round(w,2)))
    return out
def contorno(p):
    L=[];R=[]
    for i,(x,y,w) in enumerate(p):
        a=p[min(i+1,len(p)-1)]; b=p[max(i-1,0)]
        ang=math.atan2(a[1]-b[1],a[0]-b[0]); nx,ny=-math.sin(ang),math.cos(ang)
        L.append((x+nx*w/2,y+ny*w/2)); R.append((x-nx*w/2,y-ny*w/2))
    poly=L+R[::-1]
    return "%.2f %.2f m "%poly[0]+" ".join("%.2f %.2f l"%q for q in poly[1:])+" h f\n"
tr1=stilo(70,560); tr2=stilo(70,440)
dati=zlib.compress((";".join("%g,%g,%g"%q for q in tr1)+"|"+";".join("%g,%g,%g"%q for q in tr2)).encode(),9)
b64=base64.b64encode(dati).decode()
s=testo(["PROVA 3 - PAGINA 1: STILOGRAFICA","Spessore variabile (forma piena) + dati del tratto nel segnalino.","Scarabocchia sotto con Anteprima, poi Fine."])
s+="0.5 0.5 0.5 RG 1 w 60 300 m 535 300 l S\n"
s+="q\n"+marca("APT-INIZIO v2 n3 p1 D:"+b64)+"0.05 0.1 0.45 rg\n"+contorno(tr1)+"0 0 0 rg\n"+contorno(tr2)
s+="q /GsH gs 1 J 1 1 0 RG 14 w 60 735 m 400 735 l S Q\n"+marca("APT-FINE")+"Q\n"
res=Dictionary(Font=Dictionary(F1=font),ExtGState=Dictionary(GsH=gsH))
pdf.pages.append(pikepdf.Page(Dictionary(Type=Name.Page,MediaBox=Array([0,0,W,H]),Resources=res,Contents=pdf.make_stream(s.encode()))))
# ---- PAGINA 2: FOTO intera + FOTO ritagliata (stessa immagine, parte esterna tagliata)
random.seed(1)
img=Image.new("RGB",(1600,1200))
d=ImageDraw.Draw(img)
for y in range(1200):
    d.line([(0,y),(1600,y)],fill=(int(40+150*y/1200),int(90+80*math.sin(y/90)**2),int(200-120*y/1200)))
for k in range(60):
    x,y,r=random.randint(0,1600),random.randint(0,1200),random.randint(10,90)
    d.ellipse([x-r,y-r,x+r,y+r],outline=(random.randint(0,255),)*3,width=3)
for gx in range(0,1600,8): d.line([(gx,0),(gx,40)],fill=(0,0,0) if gx%16 else (255,255,255))  # righe sottilissime: test nitidezza
fnt=ImageFont.load_default()
for i in range(20): d.text((30,60+i*55),"NITIDEZZA riga %02d - dettaglio fine 0123456789"%i,fill=(255,255,255),font=fnt)
d.rectangle([1150,800,1550,1150],fill=(220,30,30)); d.text((1200,950),"PARTE TAGLIATA",fill=(255,255,255),font=fnt)
buf=io.BytesIO(); img.save(buf,"JPEG",quality=90); jpg=buf.getvalue()
xo=pdf.make_stream(jpg); xo.Type=Name.XObject; xo.Subtype=Name.Image; xo.Width=1600; xo.Height=1200
xo.ColorSpace=Name.DeviceRGB; xo.BitsPerComponent=8; xo.Filter=Name.DCTDecode
open("foto-originale.jpg","wb").write(jpg)
s=testo(["PROVA 3 - PAGINA 2: FOTO","In alto foto intera, in basso la stessa foto RITAGLIATA (manca il riquadro rosso).","Scarabocchia con Anteprima, poi Fine."])
s+="q\n"+marca("APT-INIZIO v2 n2 p2")
s+="q 400 0 0 300 98 400 cm /Im1 Do Q\n"                      # intera: 4 px/pt
s+="q 98 60 260 220 re W n 400 0 0 300 98 0 cm /Im1 Do Q\n"   # ritagliata: si disegna tutta ma si vede solo il riquadro
s+=marca("APT-FINE")+"Q\n"
res=Dictionary(Font=Dictionary(F1=font),XObject=Dictionary(Im1=xo))
pdf.pages.append(pikepdf.Page(Dictionary(Type=Name.Page,MediaBox=Array([0,0,W,H]),Resources=res,Contents=pdf.make_stream(s.encode()))))
pdf.save("Prova-3-stilografica-foto.pdf")
print(len(b64),"caratteri di dati; jpg",len(jpg))
