import sys
import warnings

warnings.filterwarnings("ignore")

from pdf2docx import Converter

src, dst = sys.argv[1], sys.argv[2]
cv = Converter(src)
try:
    cv.convert(dst)
finally:
    cv.close()
