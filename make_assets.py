# 產生圓角遮罩與白框 PNG（尺寸與 install.command 內的版面數值一致）
from PIL import Image, ImageDraw, ImageFilter
import os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
W, H, R, B, P = 480, 436, 48, 6, 30   # 可見鏡頭寬高、圓角、白框粗細、陰影留白
SS = 4                                # 超取樣讓邊緣平滑

def rrect(size, box, radius, fill, mode="L", bg=0):
    im = Image.new(mode, (size[0]*SS, size[1]*SS), bg)
    ImageDraw.Draw(im).rounded_rectangle([v*SS for v in box], radius*SS, fill=fill)
    return im.resize(size, Image.LANCZOS)

# 遮罩：16:9，中間白色圓角矩形（OBS 會把遮罩拉伸到鏡頭解析度）
mw, mh = 1920, 1080
vw = mh * W / H
x0 = (mw - vw) / 2
rrect((mw, mh), (x0, 0, x0 + vw, mh), R * mh / H, 255).convert("RGB").save(f"{OUT}/cam_mask.png")

# 外框：柔和陰影 + 白色圓角框
fw, fh = W + 2*B + 2*P, H + 2*B + 2*P
shadow = rrect((fw, fh), (P, P + 8, P + W + 2*B, P + H + 2*B + 8), R + B, 110).filter(ImageFilter.GaussianBlur(14))
frame = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
frame.paste((0, 0, 0, 255), (0, 0), shadow)
white = rrect((fw, fh), (P, P, P + W + 2*B, P + H + 2*B), R + B, 235)
frame.paste((255, 255, 255, 255), (0, 0), white)
frame.save(f"{OUT}/cam_frame.png")
print("frame", fw, fh)
