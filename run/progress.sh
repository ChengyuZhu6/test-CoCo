source run/common.bash
csv_file="$TEST_COCO_PATH/../report/report.csv"
summary_result() {
    local file_path="$1"
    local log_path="$2"
    local tests=$(sed -n '/testsuite name=/=' $file_path)
    local bats_name=""
    local number_all=""
    local number_success=""
    local number_failures=""
    local number_errors=""
    local number_skipped=""
    local running_time=""
    local success_rate=""
    bats_name=$(sed -n ${tests}p $file_path | grep 'name' | awk -F '=' '{print $2}' | cut -d ' ' -f1 | cut -d '.' -f1 | cut -d '"' -f2)
    echo $bats_name
    number_all=$(sed -n ${tests}p $file_path | grep 'tests' | awk -F '=' '{print $3}' | cut -d ' ' -f1 | cut -d '.' -f1 | cut -d '"' -f2)
    echo $number_all
    number_failures=$(sed -n ${tests}p $file_path | grep 'failures' | awk -F '=' '{print $4}' | cut -d ' ' -f1 | cut -d '.' -f1 | cut -d '"' -f2)
    echo $number_failures
    number_errors=$(sed -n ${tests}p $file_path | grep 'errors' | awk -F '=' '{print $5}' | cut -d ' ' -f1 | cut -d '.' -f1 | cut -d '"' -f2)
    echo $number_errors
    number_skipped=$(sed -n ${tests}p $file_path | grep 'skipped' | awk -F '=' '{print $6}' | cut -d ' ' -f1 | cut -d '.' -f1 | cut -d '"' -f2)
    echo $number_skipped
    running_time=$(sed -n ${tests}p $file_path | grep 'time' | awk -F '=' '{print $7}' | cut -d ' ' -f1 | cut -d '"' -f2)
    echo $running_time
    number_success=$(($number_all - $number_failures - $number_errors - $number_skipped))
    echo $number_success
    success_rate=`echo "scale=2; $number_success/$number_all*100" | bc`
    echo $success_rate
    echo "$bats_name,$number_all,$number_success,$number_failures,$number_errors,$number_skipped,"$success_rate\%","${running_time}s",$log_path" |tee -a $csv_file
}
split_content() {
    local file_path="$TEST_COCO_PATH/../report/junit.log"
    local res=$(sed -n '/xml/=' $file_path)
    local tests=$(sed -n '/testsuite name=/=' $file_path)
    local nu_res=(${res// /})
    local tests_res=(${tests// /})
    local len=${#nu_res[@]}
    local count=0
    local file_name=""
    cat /dev/null > $csv_file
    echo "Test_Category,Planned_Total,Success,Failures,Errors,Skipped,Pass,Time,Log"|tee -a $csv_file
    for n in ${nu_res[@]}; do
        if [ $count -lt $(($len - 1)) ]; then
            name=$(sed -n ${tests_res[$count]}p $file_path | grep 'name' | awk -F '=' '{print $2}' | cut -d ' ' -f1 | cut -d '.' -f1 | cut -d '"' -f2)
            tails_xml=${nu_res[$(($count + 1))]}
            last_xml=$((${tails_xml} - 1))
            sed -n "$n,${last_xml}p" $file_path >$TEST_COCO_PATH/../report/$name.xml
            summary_result $TEST_COCO_PATH/../report/$name.xml ${name}-report.html
            xunit-viewer -r $TEST_COCO_PATH/../report/$name.xml -t "Result Test" -o $TEST_COCO_PATH/../report/view/${name}-report.html
        else
            name=$(sed -n ${tests_res[$count]}p $file_path | grep 'name' | awk -F '=' '{print $2}' | cut -d ' ' -f1 | cut -d '.' -f1 | cut -d '"' -f2)
            tail -n +$n $file_path >$TEST_COCO_PATH/../report/$name.xml
            summary_result $TEST_COCO_PATH/../report/$name.xml ${name}-report.html
            xunit-viewer -r $TEST_COCO_PATH/../report/$name.xml -t "Result Test" -o $TEST_COCO_PATH/../report/view/${name}-report.html
        fi
        count=$(($count + 1))
    done
    generate_xls
}

generate_xls() {
    python3 $TEST_COCO_PATH/../run/generate_xls.py $csv_file
    rm $TEST_COCO_PATH/../report/*.xml
}
split_content
