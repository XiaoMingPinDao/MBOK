export default {
  title: 'Antlia',
  description: '轻量级脚本项目部署工具',
  head: [
    ['link', { rel: 'icon', type: 'image/x-icon', href: '/favicon.ico' }],
    ['link', { rel: 'icon', type: 'image/png', sizes: '16x16', href: '/favicon-16x16.png' }],
    ['link', { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/favicon-32x32.png' }],
    ['link', { rel: 'apple-touch-icon', sizes: '180x180', href: '/logo.png' }],
    ['meta', { name: 'theme-color', content: '#3eaf7c' }],
  ],
  themeConfig: {
    logo: '/logo.png',
    nav: [
      { text: '指南', link: '/guide' },
      { text: 'GitHub', link: 'https://github.com/zhende1113/Antlia' },
    ],
    sidebar: {
      '/': [
        {
          text: 'Bot项目相关',
          items: [
            { text: 'AstrBot', link: '/AstrBot/AstrBot-install' },
            { text: 'Eridanus', link: '/AstrBot/Eridanus' },
            { text: 'NapCat', link: '/AstrBot/NapCat' },
            { text: 'Lagange.OneBot', link: '/AstrBot/Lagange-OneBot' },
          ]
        },
        {
          text: '其他功能',
          items: [
            { text: '项目脚本状态', link: '/guide' },
          ]
        }
      ]
    }
  },
}