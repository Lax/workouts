import { bootstrap } from '@workouts/core'
import config from '../../config.json'
import helloWorldTheme from '@workouts/theme-hello-world'

bootstrap(config, 'hello', { theme: helloWorldTheme })
