source $(pwd)/run/common.bash
csv_file="$TEST_COCO_PATH/../report/report.csv"
all_tests=0
all_success=0
all_failures=0
all_error=0
all_skipped=0
all_time=0
all_success_rate=0
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
    all_tests=$(($all_tests + $number_all))
    number_failures=$(sed -n ${tests}p $file_path | grep 'failures' | awk -F '=' '{print $4}' | cut -d ' ' -f1 | cut -d '.' -f1 | cut -d '"' -f2)
    echo $number_failures
    all_failures=$(($all_failures + $number_failures))
    number_errors=$(sed -n ${tests}p $file_path | grep 'errors' | awk -F '=' '{print $5}' | cut -d ' ' -f1 | cut -d '.' -f1 | cut -d '"' -f2)
    echo $number_errors
    all_error=$(($all_error + $number_errors))
    number_skipped=$(sed -n ${tests}p $file_path | grep 'skipped' | awk -F '=' '{print $6}' | cut -d ' ' -f1 | cut -d '.' -f1 | cut -d '"' -f2)
    echo $number_skipped
    all_skipped=$(($all_skipped + $number_skipped))
    running_time=$(sed -n ${tests}p $file_path | grep 'time' | awk -F '=' '{print $7}' | cut -d ' ' -f1 | cut -d '"' -f2)
    echo $running_time
    all_time=$(echo "scale=2; ($all_time + $running_time)" | bc)
    number_success=$(($number_all - $number_failures - $number_errors - $number_skipped))
    echo $number_success
    all_success=$(($all_success + $number_success))
    success_rate=$(echo "scale=2; $number_success/$number_all*100" | bc)
    echo $success_rate
    echo "$bats_name,$number_all,$number_success,$number_failures,$number_errors,$number_skipped,"$success_rate\%","${running_time}s",$log_path" | tee -a $csv_file
}
split_content() {
    local nu_res=$(find $TEST_COCO_PATH/../report/ -name '*.xml' | wc -l)
    local tests_res=$(ls -lrt $TEST_COCO_PATH/../report/*.xml | awk '{print $9}')
    local file_name=""
    cat /dev/null >$csv_file
    echo "Test_Category,Planned_Total,Success,Failures,Errors,Skipped,Pass,Time,Log" | tee -a $csv_file
    for t in ${tests_res[@]}; do
        echo $t
        summary_result $t "$(basename $t).html"
        xunit-viewer -r $t -t "Result Test" -o "$TEST_COCO_PATH/../report/view/$(basename $t).html"
    done
    all_success_rate=$(echo "scale=2; $all_success/$all_tests*100" | bc)
    echo "Summary,$all_tests,$all_success,$all_failures,$all_error,$all_skipped,"$all_success_rate\%","${all_time}s",''" | tee -a $csv_file

    generate_xls
}

generate_xls() {
    python3 $TEST_COCO_PATH/../run/generate_xls.py $csv_file
    # rm $TEST_COCO_PATH/../report/*.xml
}
split_content
