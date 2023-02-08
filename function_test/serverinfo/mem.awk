$0~ /Size.*[0-9]/ {printf "%s",$0"\t"} 
$0~ /Speed.*[0-9]/ {printf "%s",$0"\t\t\n"} 
