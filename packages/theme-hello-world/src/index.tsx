import type { ThemePlugin, ThemeProps } from '@workouts/core'

function HelloWorldLayout({ data }: ThemeProps) {
  return (
    <div style={{
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      height: '100vh',
      color: 'var(--color-text, #e0e0e0)',
      background: 'var(--color-bg, #121212)',
    }}>
      <h1 style={{ fontSize: '2rem', marginBottom: '1rem' }}>Hello World</h1>
      <p>Activities loaded: {data.activities?.length ?? 0}</p>
    </div>
  )
}

const theme: ThemePlugin = {
  type: 'theme',
  manifest: { id: 'hello-world', name: 'Hello World', version: '0.1.0' },
  Layout: HelloWorldLayout,
}

export default theme
