import { useState } from 'react'
import { useSimpleStore } from '../store'

interface NavLinkItem {
  name: string
  url?: string
  children?: { name: string; url: string }[]
}

interface SiteConfig {
  title: string
  url: string
  logo: string | null
  navLinks: NavLinkItem[]
}

export function Header({ config }: { config: SiteConfig }) {
  const colorScheme = useSimpleStore((s) => s.colorScheme)
  const toggleTheme = useSimpleStore((s) => s.toggleTheme)
  const view = useSimpleStore((s) => s.view)
  const setView = useSimpleStore((s) => s.setView)
  const [menuOpen, setMenuOpen] = useState(false)

  const githubUser = import.meta.env.VITE_GITHUB_USER

  return (
    <header className="simple-header">
      <div className="logo-area">
        {config.logo ? (
          <a href={config.url}>
            <img className="logo-img" src={config.logo} alt={config.title} />
          </a>
        ) : githubUser ? (
          <a href={config.url}>
            <img className="logo-img" src={`https://github.com/${githubUser}.png`} alt={config.title} />
          </a>
        ) : (
          <a className="logo-text" href={config.url}>
            {config.title}
          </a>
        )}
      </div>
      <div className="nav-area">
        {view === 'main' && (
          <button type="button" className="header-btn" onClick={() => setView('summary')} aria-label="Summary">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              strokeWidth={1.5}
              stroke="currentColor"
              width={20}
              height={20}
              aria-hidden="true"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                d="M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 0 1 3 19.875v-6.75ZM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V8.625ZM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V4.125Z"
              />
            </svg>
          </button>
        )}
        <button type="button" className="header-btn" onClick={toggleTheme} aria-label="Toggle theme">
          {colorScheme === 'dark' ? (
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              strokeWidth={1.5}
              stroke="currentColor"
              width={20}
              height={20}
              aria-hidden="true"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                d="M12 3v2.25m6.364.386-1.591 1.591M21 12h-2.25m-.386 6.364-1.591-1.591M12 18.75V21m-4.773-4.227-1.591 1.591M5.25 12H3m4.227-4.773L5.636 5.636M15.75 12a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z"
              />
            </svg>
          ) : (
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              strokeWidth={1.5}
              stroke="currentColor"
              width={20}
              height={20}
              aria-hidden="true"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                d="M21.752 15.002A9.72 9.72 0 0 1 18 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 0 0 3 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 0 0 9.002-5.998Z"
              />
            </svg>
          )}
        </button>
        <div className="header-dropdown">
          <button type="button" className="header-btn" onClick={() => setMenuOpen(!menuOpen)} aria-label="Menu" aria-expanded={menuOpen}>
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              strokeWidth={1.5}
              stroke="currentColor"
              width={20}
              height={20}
              aria-hidden="true"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                d={menuOpen ? 'M6 18 18 6M6 6l12 12' : 'M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5'}
              />
            </svg>
          </button>
          {menuOpen && (
            <>
              <div className="header-dropdown-backdrop" onClick={() => setMenuOpen(false)} />
              <div className="header-dropdown-menu">
                {config.navLinks.map((item) =>
                  item.children ? (
                    <div key={item.name} className="header-dropdown-group">
                      <div className="header-dropdown-group-label">{item.name}</div>
                      {item.children.map((child) => (
                        <a key={child.url} className="header-dropdown-item" href={child.url} onClick={() => setMenuOpen(false)}>
                          {child.name}
                        </a>
                      ))}
                    </div>
                  ) : (
                    <a key={item.url} className="header-dropdown-item" href={item.url!} onClick={() => setMenuOpen(false)}>
                      {item.name}
                    </a>
                  ),
                )}
              </div>
            </>
          )}
        </div>
      </div>
    </header>
  )
}
