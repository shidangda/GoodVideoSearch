// PM2 配置文件
// 使用 .cjs 扩展名，因为项目使用 ES 模块（package.json 中 "type": "module"）
// PM2 需要使用 CommonJS 格式加载配置文件
module.exports = {
  apps: [
    {
      name: 'goodvideosearch',
      script: 'src/app.js',
      instances: 1,
      exec_mode: 'fork',
      // 加载 .env 文件（PM2 5.1+ 支持）
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

