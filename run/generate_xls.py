import xlwt
import sys
import csv
print(len(sys.argv[1]))
csv_file_path= str(sys.argv[1])
wbk = xlwt.Workbook(encoding="utf-8") # 创建 xls 文件,可被复写
datasheet = wbk.add_sheet("Function_tests") # 创建一个名为sheet1的sheet
# 设置单元格的样式，如字体、背景颜色等等
head_style = xlwt.XFStyle()
head_font = xlwt.Font()
head_font.name='Times New Roman'
head_font.bold = True
head_font.height=12*20
head_font.colour_index=0x1B
head_style.font=head_font
head_pattern=xlwt.Pattern()
head_pattern.pattern=xlwt.Pattern.SOLID_PATTERN
head_pattern.pattern_fore_colour=0x47
head_style.pattern=head_pattern
head_al = xlwt.Alignment()
head_al.horz = 0x02      # 设置水平居中0x02，左端对齐0x01，右端对齐0x03
head_al.vert = 0x01      # 设置垂直居中 0x01，上端对齐0x00，底端对齐0x02
# head_al.wrap = 1
head_style.alignment = head_al
borders = xlwt.Borders() 
# 设置边框样式，常用：DASHED虚线，THIN实线，NO_LINE没有线
borders.left = xlwt.Borders.THIN 
borders.right = xlwt.Borders.THIN
borders.top = xlwt.Borders.THIN
borders.bottom = xlwt.Borders.THIN
head_style.borders=borders

cell_style = xlwt.XFStyle()
cell_font = xlwt.Font()
cell_font.name='Times New Roman'
cell_font.height=11*20
cell_style.font=cell_font
cell_pattern=xlwt.Pattern()
# pattern.pattern=xlwt.Pattern.SOLID_PATTERN
# cell_pattern.pattern_fore_colour=40
cell_style.pattern=cell_pattern
cell_al = xlwt.Alignment()
cell_al.horz = 0x02      # 设置水平居中0x02，左端对齐0x01，右端对齐0x03
cell_al.vert = 0x01      # 设置垂直居中 0x01，上端对齐0x00，底端对齐0x02
# cell_al.wrap = 1
cell_style.alignment = cell_al
cell_style.borders=borders

from collections import namedtuple
with open(csv_file_path) as f:
    f_csv = csv.reader(f)
    headings = next(f_csv)
    co=0
    ro=0
    params_len = len(headings)
    for heads in headings:
        datasheet.write(ro, co, heads,head_style)
        datasheet.col(ro).width = 15*256
        co = co + 1
    datasheet.col(0).width = 27*256
    datasheet.col(1).width = 15*256
    ro=1
    co=0
    for row in f_csv:
        for r in row:
            if co == params_len - 1: 
                datasheet.write(ro, co, xlwt.Formula('HYPERLINK("%s";"html")'%("./view/"+r)),cell_style)
            else:
                datasheet.write(ro, co, r,cell_style)
            co = co + 1
        ro = ro + 1
        co = 0

base_dir_path=csv_file_path.rsplit('/',1)[0]
file_name=csv_file_path.rsplit('/',1)[1]
names=file_name.rsplit('.',3)[0]
wbk.save(base_dir_path+"/"+names+"/Function_Test_Result_of_CoCo_on_MVP.xls") # 保存