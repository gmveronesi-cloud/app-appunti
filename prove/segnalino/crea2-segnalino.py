import pikepdf, math
from pikepdf import Name, Dictionary, Array
pdf=pikepdf.new(); W,H=595,842
font=pdf.make_indirect(Dictionary(Type=Name.Font,Subtype=Name.Type1,BaseFont=Name.Helvetica,Encoding=Name.WinAnsiEncoding))
gsH=pdf.make_indirect(Dictionary(Type=Name.ExtGState,CA=0.35,ca=0.35))
gs0=pdf.make_indirect(Dictionary(Type=Name.ExtGState,CA=0,ca=0))
def onda(x0,y0,l,a,per,n=60):
    p=[(x0+l*i/n,y0+a*math.sin(2*math.pi*i/n*per)) for i in range(n+1)]
    return "%.2f %.2f m "%p[0]+" ".join("%.2f %.2f l"%q for q in p[1:])+" S\n"
def tratti():
    s="1 J 1 j 0 0 0 RG 1.6 w\n"+onda(80,560,430,14,3)
    s+="0.1 0.3 0.8 RG 2.4 w\n"+onda(80,500,430,10,5)
    s+="q /GsH gs 2 J 1 1 0 RG 16 w 70 704 m 470 704 l S Q\n"
    return s
def marca(t, modo):
    if modo==1: return "BT /F1 1 Tf 3 Tr 1 0 0 1 2 2 Tm (%s) Tj ET\n"%t      # testo invisibile (come OCR)
    return "q /Gs0 gs BT /F1 1 Tf 0 Tr 1 0 0 1 2 2 Tm (%s) Tj ET Q\n"%t          # testo trasparente
for n,(tit,modo) in enumerate([("PAGINA 1 - segnalino: testo invisibile",1),("PAGINA 2 - segnalino: testo trasparente",2)],1):
    s="BT /F1 13 Tf 0 0 0 rg 1 0 0 1 72 740 Tm (%s) Tj 1 0 0 1 72 718 Tm (Testo stampato. Scarabocchia sotto, poi Fine.) Tj ET\n"%tit
    s+="0.5 0.5 0.5 RG 1 w 72 300 m 520 300 l S\n"   # grafica ORIGINALE della pagina (non nostra)
    s+="q\n"+marca("APT-INIZIO v1 n3 p%d"%n,modo)+tratti()+marca("APT-FINE",modo)+"Q\n"
    res=Dictionary(Font=Dictionary(F1=font),ExtGState=Dictionary(GsH=gsH,Gs0=gs0))
    pdf.pages.append(pikepdf.Page(Dictionary(Type=Name.Page,MediaBox=Array([0,0,W,H]),Resources=res,Contents=pdf.make_stream(s.encode()))))
pdf.save("Prova-segnalino.pdf")
