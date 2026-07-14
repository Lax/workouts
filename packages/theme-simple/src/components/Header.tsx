import { useSimpleStore } from '../store'

interface NavLink {
  name: string
  url: string
}

interface SiteConfig {
  title: string
  url: string
  logo: string | null
  navLinks: NavLink[]
}

export function Header({ config }: { config: SiteConfig }) {
  const colorScheme = useSimpleStore((s) => s.colorScheme)
  const toggleTheme = useSimpleStore((s) => s.toggleTheme)

  return (
    <header className="simple-header">
      <div className="logo-area">
        {config.logo ? (
          <a href={config.url}>
            <img className="logo-img" src={config.logo} alt={config.title} />
          </a>
        ) : (
          <a className="logo-text" href={config.url}>
            {config.title}
          </a>
        )}
      </div>
      <div className="nav-area">
        {config.navLinks.map((n) => (
          <a key={n.url} className="nav-link" href={n.url}>
            {n.name}
          </a>
        ))}
        <button type="button" className="theme-btn" onClick={toggleTheme} aria-label="Toggle theme">
          {colorScheme === 'dark' ? '☀️' : '🌙'}
        </button>
      </div>
    </header>
  )
}
