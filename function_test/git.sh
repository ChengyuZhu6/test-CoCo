git add .
git reset -- start.sh
git reset -- k8s_non_tee_cc.sh
git reset -- logs.log
git commit -am "$1" -s
git push origin $2
