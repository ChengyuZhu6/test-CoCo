#!/usr/bin/env bash

source $(pwd)/run/common.bash
file_base_dir="$TEST_COCO_PATH/../report"
sub_dir=""
image_type="un"
csv_file="report.csv"
all_tests=0
all_success=0
all_failures=0
all_error=0
all_skipped=0
all_time=0
all_success_rate=0
all_concurrency=()
all_image=()
all_pod_spec=()
summary_result_for_function() {
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
    csv_file_for_function=$file_base_dir/$sub_dir/$csv_file
    echo "$bats_name,$number_all,$number_success,$number_failures,$number_errors,$number_skipped,"$success_rate\%","${running_time}s",$log_path" | tee -a $csv_file_for_function
    generate_xls $csv_file_for_function
}

summary_result_for_concurrency() {
    local file_path="$1"
    local tests=$(sed -n '/testsuite name=/=' $file_path)
    local bats_name=""
    local pod_num=""
    local sub_line=$(sed -n '/testcase classname=/=' $file_path)
    csv_file_for_concurrency=$file_base_dir/$sub_dir/$csv_file
    bats_name=$(sed -n ${tests}p $file_path | grep 'name' | awk -F '=' '{print $2}' | cut -d ' ' -f1 | cut -d '.' -f1 | cut -d '"' -f2)
    echo $bats_name
    local input_str="$bats_name"

    for ns in ${sub_line[@]}; do
        pod_num=$(sed -n ${ns}p $file_path | grep ' name=' | awk -F '=' '{print $3}' | cut -d ' ' -f5 | cut -d 'P' -f1)
        running_time=$(sed -n ${ns}p $file_path | grep ' time=' | awk -F '=' '{print $4}' | cut -d ' ' -f1 | cut -d '"' -f2)
        pos=$(($pod_num - 1))
        all_concurrency[$pos]=$(echo "scale=3; ${all_concurrency[$pos]} + $running_time" | bc)
    done
    concurrency_nums=$(jq -r '.config.podNum[]' $TEST_COCO_PATH/../config/test_config.json)
    for COUNTS in ${concurrency_nums[@]}; do
        input_str=$input_str","${all_concurrency[$(($COUNTS - 1))]}
    done
    for COUNTS in ${concurrency_nums[@]}; do
        all_concurrency[$(($COUNTS - 1))]=0
    done
    echo "$input_str" | tee -a $csv_file_for_concurrency
    generate_xls $csv_file_for_concurrency
}
summary_result_for_image() {
    local file_path="$1"
    local log_path="$2"
    local tests=$(sed -n '/testsuite name=/=' $file_path)
    local bats_name=""
    local image_size=""
    local number_all=""
    local sub_line=$(sed -n '/testcase classname=/=' $file_path)
    csv_file_for_pod_spec=$file_base_dir/$sub_dir/$csv_file
    bats_name=$(sed -n ${tests}p $file_path | grep 'name' | awk -F '=' '{print $2}' | cut -d ' ' -f1 | cut -d '.' -f1 | cut -d '"' -f2)
    echo $bats_name
    local input_str="$bats_name"

    for ns in ${sub_line[@]}; do
        image_size=$(sed -n ${ns}p $file_path | grep ' name=' | awk -F '=' '{print $3}' | cut -d ' ' -f2 | cut -d '-' -f2 | sed 's/[^0-9 ]//g')
        running_time=$(sed -n ${ns}p $file_path | grep ' time=' | awk -F '=' '{print $4}' | cut -d ' ' -f1 | cut -d '"' -f2)
        pos=$(($image_size - 1))
        all_image[$pos]=$(echo "scale=3; ${all_image[$pos]} + $running_time" | bc)
    done
    image_lists=$(jq -r .file.imageLists[] $TEST_COCO_PATH/../config/test_config.json)
    for img in ${image_lists[@]}; do
        SIZES=$(echo $img | sed 's/[^0-9 ]//g')
        input_str=$input_str","${all_image[$(($SIZES - 1))]}
    done
    for img in ${image_lists[@]}; do
        SIZES=$(echo $img | sed 's/[^0-9 ]//g')
        all_image[$(($SIZES - 1))]=0
    done
    echo "$input_str" | tee -a $csv_file_for_image

    generate_xls $csv_file_for_image
}
summary_result_for_pod_spec() {
    local file_path="$1"
    local tests=$(sed -n '/testsuite name=/=' $file_path)
    local sub_line=$(sed -n '/testcase classname=/=' $file_path)
    csv_file_for_pod_spec=$file_base_dir/$sub_dir/$3/$csv_file
    local input_str=""
    mem_nums=$(jq -r '.config.memSize[]' $TEST_COCO_PATH/../config/test_config.json)
    cpu_nums=$(jq -r '.config.cpuNum[]' $TEST_COCO_PATH/../config/test_config.json)
    echo $sub_line
    for ns in ${sub_line[@]}; do
        mem_size=$(sed -n ${ns}p $file_path | grep ' name=' | awk -F '=' '{print $3}' | cut -d ' ' -f7 | cut -d '"' -f1 | sed 's/[^0-9 ]//g')
        echo $men_size
        cpu_num=$(sed -n ${ns}p $file_path | grep ' name=' | awk -F '=' '{print $3}' | cut -d ' ' -f6 | cut -d '"' -f1 | sed 's/[^0-9 ]//g')
        running_time=$(sed -n ${ns}p $file_path | grep ' time=' | awk -F '=' '{print $4}' | cut -d ' ' -f1 | cut -d '"' -f2)
        echo $men_size"+"$cpu_num
        all_pod_spec[$men_size"+"$cpu_num]=$running_time
    done

    for mem_size in ${mem_nums[@]}; do
        input_str="$mem_size"
        for cpu_num in ${cpu_nums[@]}; do
            input_str=$input_str","${all_pod_spec[$men_size"+"$cpu_num]}
        done
        echo "$input_str" | tee -a $csv_file_for_pod_spec
    done

    generate_xls $csv_file_for_pod_spec
}
split_content_for_function() {
    local nu_res=$(find $1/$2 -name '*.xml' | wc -l)
    local tests_res=$(ls -lrt $1/$2/*.xml | awk '{print $9}')
    local file_name=""

    if [ ! -d $1/view/$2 ]; then
        mkdir $1/view/$2
    fi
    csv_file_for_function=$1/$2/$csv_file
    cat /dev/null >$csv_file_for_function
    echo "$3" | tee -a $csv_file_for_function
    for t in ${tests_res[@]}; do
        summary_result_for_function $t "$(basename $t).html"
        xunit-viewer -r $t -t "Result Test" -o "$1/view/$2/$(basename $t).html"
    done
    all_success_rate=$(echo "scale=2; $all_success/$all_tests*100" | bc)
    echo "Summary,$all_tests,$all_success,$all_failures,$all_error,$all_skipped,"$all_success_rate\%","${all_time}s",''" | tee -a $csv_file

    generate_xls $csv_file_for_function
}
split_content_for_concurrency() {
    local nu_res=$(find $1/$2 -name '*.xml' | wc -l)
    local tests_res=$(ls -lrt $1/$2/*.xml | awk '{print $9}')
    local file_name=""
    if [ ! -d $1/view/$2 ]; then
        mkdir $1/view/$2
    fi

    csv_file_for_concurrency=$1/$2/$csv_file
    cat /dev/null >$csv_file_for_concurrency
    echo "$3" | tee -a $csv_file_for_concurrency
    for t in ${tests_res[@]}; do
        summary_result_for_concurrency $t "$(basename $t).html"
        xunit-viewer -r $t -t "Result Test" -o "$1/view/$2/$(basename $t).html"
    done
}
split_content_for_image() {
    local nu_res=$(find $1/$2 -name '*.xml' | wc -l)
    local tests_res=$(ls -lrt $1/$2/*.xml | awk '{print $9}')
    local file_name=""
    if [ ! -d $1/view/$2 ]; then
        mkdir $1/view/$2
    fi

    csv_file_for_image=$1/$2/$csv_file
    cat /dev/null >$csv_file_for_image
    echo "$3" | tee -a $csv_file_for_image
    for t in ${tests_res[@]}; do
        summary_result_for_image $t "$(basename $t).html"
        xunit-viewer -r $t -t "Result Test" -o "$1/view/$2/$(basename $t).html"
    done
}
split_content_for_pod_spec() {
    local tests_res=$(ls -lrt $1/$2/*.xml | awk '{print $9}')
    local file_name=""
    for t in ${tests_res[@]}; do
        image_types=$(basename $t| cut -d '.' -f1)
        if [ ! -d $1/view/$2 ]; then
            mkdir -p $1/view/$2/$image_types
        fi
        if [ ! -d $1/$2/$image_types ]; then
            mkdir -p $1/$2/$image_types
        fi
        csv_file_for_pod_spec=$1/$2/$image_types/$csv_file
        cat /dev/null >$csv_file_for_pod_spec
        echo "$3" | tee -a $csv_file_for_pod_spec
        summary_result_for_pod_spec $t "$(basename $t).html" $image_types
        xunit-viewer -r $t -t "Result Test" -o "$1/view/$2/$(basename $t).html"
    done
}
generate_xls() {
    python3 $TEST_COCO_PATH/../run/generate_xls.py $1
    # rm $TEST_COCO_PATH/../report/*.xml
}

main() {
    file_base_dir="$TEST_COCO_PATH/../report"
    sub_dir="image"
    horizontal_axis=""
    case $sub_dir in

    "concurrency")
        horizontal_axis="Category\Concurrency"
        concurrency_nums=$(jq -r '.config.podNum[]' $TEST_COCO_PATH/../config/test_config.json)
        for COUNTS in ${concurrency_nums[@]}; do
            horizontal_axis=$horizontal_axis",$COUNTS"
            all_concurrency[$(($COUNTS - 1))]=0
        done
        horizontal_axis=$horizontal_axis",Time"
        split_content_for_concurrency $file_base_dir $sub_dir $horizontal_axis
        ;;

    "image")
        horizontal_axis="Test_Category\Image_Size"
        image_lists=$(jq -r .file.imageLists[] $TEST_COCO_PATH/../config/test_config.json)
        for img in ${image_lists[@]}; do
            UNIT=$(echo $img | sed 's/[^A-Z]//g')
            SIZES=$(echo $img | sed 's/[^0-9 ]//g')
            all_image[$(($SIZES - 1))]=0
            horizontal_axis=$horizontal_axis",$SIZES${UNIT}B"
        done
        horizontal_axis=$horizontal_axis",Time"
        split_content_for_image $file_base_dir $sub_dir $horizontal_axis
        ;;

    "pod_spec")
        horizontal_axis="Memory\CPU"
        cpunums=$(jq -r '.config.cpuNum[]' $TEST_COCO_PATH/../config/test_config.json)
        for COUNTS in ${cpunums[@]}; do
            horizontal_axis=$horizontal_axis",$COUNTS"
        done
        horizontal_axis=$horizontal_axis",Time"
        split_content_for_pod_spec $file_base_dir $sub_dir $horizontal_axis 
        ;;

    "function")
        horizontal_axis="Test_Category,Planned_Total,Success,Failures,Errors,Skipped,Pass,Time,Log"
        split_content_for_function $file_base_dir $sub_dir $horizontal_axis
        ;;
    esac
}

main "$@"
