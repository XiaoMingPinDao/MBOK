import DefaultTheme from 'vitepress/theme'
import { h } from 'vue'
import './styles/custom.css'

export default {
  extends: DefaultTheme,
  Layout: () => {
    return h(DefaultTheme.Layout, null, {
      "logo-after": () => h('img', {
        src: '/logo.png',
        alt: 'Antlia Logo',
        style: 'width:40px;height:40px;border-radius:50%;object-fit:cover;'
      })
    })
  }
}
