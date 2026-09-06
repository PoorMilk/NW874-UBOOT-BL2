不要使用 git pull 更新本地源码，请使用：git fetch origin && git reset --hard origin/main，原因：main 分支自动重置同步上游，提交历史会被重写。
