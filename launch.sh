#!/bin/sh

BASE=/home/node/app
USERNAME=$(printenv username)
PASSWORD=$(printenv password)

function env() {
  # 首先尝试从环境变量直接读取
  if [[ -z "${github_secret}" ]]; then
    github_secret=$(printenv github_secret)
  fi
  
  if [[ -z "${github_project}" ]]; then
    github_project=$(printenv github_project)
  fi
  
  # 如果还是为空且设置了fetch，则从远程获取
  if [[ ! -z "${fetch}" ]] && ([[ -z "${github_secret}" ]] || [[ -z "${github_project}" ]]); then
    echo '远程获取参数...'
    curl -s "$fetch" -o data.json
    if [[ -z "${github_secret}" ]]; then
      github_secret=$(jq -r .github_secret data.json)
    fi
    if [[ -z "${github_project}" ]]; then
      github_project=$(jq -r .github_project data.json)
    fi
  fi

  if [[ -z "${USERNAME}" ]]; then
    USERNAME="root"
  fi

  if [[ -z "${PASSWORD}" ]]; then
    PASSWORD="123456"
  fi

  echo
  echo "fetch = ${fetch}"
  echo "github_secret = ${github_secret}"
  echo "github_project = ${github_project}"
  echo "USERNAME = ${USERNAME}"
  echo "PASSWORD = ${PASSWORD}"
  echo
  echo

  # 导出变量以便在其他函数中使用
  export github_secret
  export github_project
  export USERNAME
  export PASSWORD

  sed -i "s/\[github_secret\]/${github_secret}/g" launch.sh
  sed -i "s#\[github_project\]#${github_project}#g" launch.sh
}

function init() {
  echo "=== Initializing SillyTavern cloud deployment ==="
  
  # 确保环境变量被正确读取
  if [[ -z "${github_secret}" ]]; then
    github_secret=$(printenv github_secret)
  fi
  
  if [[ -z "${github_project}" ]]; then
    github_project=$(printenv github_project)
  fi
  
  # Check required environment variables
  if [[ -z "${github_secret}" ]] || [[ -z "${github_project}" ]]; then
    echo "ERROR: Missing required environment variables!"
    echo "github_secret = '${github_secret}'"
    echo "github_project = '${github_project}'"
    echo "Available environment variables:"
    printenv | grep -E "(github|secret|project)" | head -10
    echo "Please set these in Koyeb environment variables."
    exit 1
  fi
  
  mkdir ${BASE}/history
  cd ${BASE}/history

  git config --global user.email "huggingface@hf.com"
  git config --global user.name "complete-Mmx"
  git config --global init.defaultBranch main
  git init
  
  # Construct the full GitHub URL
  GITHUB_URL="https://${github_secret}@github.com/${github_project}.git"
  echo "GitHub URL: https://***@github.com/${github_project}.git"
  
  git remote add origin "${GITHUB_URL}"
  git add .
  echo "'update history$(date "+%Y-%m-%d %H:%M:%S")'"
  git commit -m "'update history$(date "+%Y-%m-%d %H:%M:%S")'" || echo "No initial commit needed"
  
  # Try to pull from remote, create initial commit if repo is empty
  if git pull origin main; then
    echo "Pulled existing data from GitHub"
  else
    echo "Remote repository is empty or doesn't exist, will push initial commit"
  fi

  cd ${BASE}

  DIR="${BASE}/history"
  if [ "$(ls -A $DIR | grep -v .git)" ]; then
    echo "Has history..."
  else
    echo "Empty history..."
    # Only copy if files exist
    if [ -d "data" ] && [ "$(ls -A data 2>/dev/null)" ]; then
      cp -r data/* history/
    fi
    if [ -f "secrets.json" ]; then
      cp secrets.json history/secrets.json
    fi
  fi

  rm -rf data
  ln -s history data

  rm -f config.yaml
  cp config/config.yaml history/config.yaml
  ln -s history/config.yaml config.yaml
  sed -i "s/username: .*/username: \"${USERNAME}\"/" ${BASE}/config.yaml
  sed -i "s/password: .*/password: \"${PASSWORD}\"/" ${BASE}/config.yaml
  # 保持 whitelistMode: true 用于安全控制
  # 添加 Koyeb 相关的域名和IP到白名单
  echo "Adding Koyeb domains to whitelist..."
  
  # 获取当前容器的IP（如果可能）
  CONTAINER_IP=$(hostname -i 2>/dev/null || echo "")
  if [ ! -z "$CONTAINER_IP" ]; then
    echo "Container IP: $CONTAINER_IP"
  fi
  
  sed -i "s/listen: false/listen: true/" ${BASE}/config.yaml
  sed -i "s/browserLaunch:/# browserLaunch (modified by launch.sh)\nbrowserLaunch:/" ${BASE}/config.yaml
  sed -i "/browserLaunch:/,/enabled:/ s/enabled: true/enabled: false/" ${BASE}/config.yaml
  # sed -i "s/basicAuthMode: false/basicAuthMode: true/" ${BASE}/config.yaml  # 禁用强制basic auth
  
  echo "=== Final config.yaml ==="
  cat config.yaml
  echo "========================="
  echo "Init history."
  chmod -R 777 history

  echo "Starting git-batch process..."
  echo "Command: ./git-batch --commit 10s --name git-batch --email git-batch@github.com --push 1m -p history"
  nohup ./git-batch --commit 10s --name git-batch --email git-batch@github.com --push 1m -p history > access.log 2>&1 &
  GIT_BATCH_PID=$!
  echo "git-batch started with PID: $GIT_BATCH_PID"
}

function release() {
  rm -rf history
}

function update() {
  cd ${BASE}/history
  git pull origin main
  git add .
  echo "'update history$(date "+%Y-%m-%d %H:%M:%S")'"
  git commit -m "'update history$(date "+%Y-%m-%d %H:%M:%S")'"
  git push origin main
}

case $1 in
  env)
    env
  ;;
  init)
    init
  ;;
  release)
    release
  ;;
  update)
    update
  ;;
esac
