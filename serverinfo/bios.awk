$0~ /Version.*/ {printf "%s",$0"\n"}
$0~ /Release Date.*/ {printf "%s",$0"\n"}
$0~ /Runtime Size.*/ {printf "%s",$0"\n"}
$0~ /ROM Size.*/ {printf "%s",$0"\n"}
$0~ /BIOS Revision.*/ {printf "%s",$0"\n"}
