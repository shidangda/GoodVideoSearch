// PM2 配置文件
module.exports = {
  apps: [
    {
      name: 'goodvideosearch',
      script: 'src/app.js',
      instances: 1,
      exec_mode: 'fork',
      // 加载 .env 文件（Node.js 18+ 支持）
      env_file: '.env',
      env: {
        NODE_ENV: 'production',
        PORT: 3000,
      },
      // 日志配置
      error_file: './logs/err.log',
      out_file: './logs/out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      // 自动重启配置
      watch: false,
      max_memory_restart: '500M',
      // 其他配置
      min_uptime: '10s',
      max_restarts: 10,
      restart_delay: 4000,
    },
  ],
};

