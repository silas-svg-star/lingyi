/*
Copyright (C) 2023-2026 QuantumNous

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.

For commercial licensing, please contact support@quantumnous.com
*/
import { Link } from '@tanstack/react-router'
import { Check } from 'lucide-react'
import { useTranslation } from 'react-i18next'

import { Skeleton } from '@/components/ui/skeleton'
import { useSystemConfig } from '@/hooks/use-system-config'

type AuthLayoutProps = {
  children: React.ReactNode
}

const HIGHLIGHTS = [
  'One key for mainstream AI models',
  'Singapore node, stable and fast',
  'Pay as you go, transparent billing',
  'Works with Cherry Studio and other OpenAI-compatible tools',
]

export function AuthLayout({ children }: AuthLayoutProps) {
  const { t } = useTranslation()
  const { systemName, logo, loading } = useSystemConfig()

  const brand = (
    <Link
      to='/'
      className='flex items-center gap-2 transition-opacity hover:opacity-80'
    >
      <div className='relative h-9 w-9'>
        {loading ? (
          <Skeleton className='absolute inset-0 rounded-full' />
        ) : (
          <img
            src={logo}
            alt={t('Logo')}
            className='h-9 w-9 rounded-full object-cover shadow-sm'
          />
        )}
      </div>
      {loading ? (
        <Skeleton className='h-6 w-24' />
      ) : (
        <h1 className='text-xl font-semibold'>{systemName}</h1>
      )}
    </Link>
  )

  return (
    <div className='bg-muted/40 relative grid min-h-svh lg:grid-cols-[minmax(0,5fr)_minmax(0,6fr)]'>
      {/* Brand panel, desktop only; colors follow the active theme preset */}
      <aside className='from-primary via-primary/85 to-primary/60 text-primary-foreground relative hidden overflow-hidden bg-gradient-to-br p-12 lg:flex lg:flex-col lg:justify-between'>
        <div
          aria-hidden='true'
          className='pointer-events-none absolute -top-24 -right-24 h-80 w-80 rounded-full bg-white/10 blur-2xl'
        />
        <div
          aria-hidden='true'
          className='pointer-events-none absolute -bottom-32 -left-20 h-96 w-96 rounded-full bg-white/10 blur-3xl'
        />
        <div className='[&_h1]:text-primary-foreground relative'>{brand}</div>
        <div className='relative space-y-6'>
          <h2 className='text-4xl leading-tight font-bold tracking-tight'>
            {t('One API, all mainstream models')}
          </h2>
          <ul className='space-y-3 text-base opacity-90'>
            {HIGHLIGHTS.map((item) => (
              <li key={item} className='flex items-start gap-3'>
                <span className='mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-white/20'>
                  <Check className='h-3.5 w-3.5' aria-hidden='true' />
                </span>
                {t(item)}
              </li>
            ))}
          </ul>
        </div>
        <p className='relative text-sm opacity-70'>
          © {new Date().getFullYear()} {systemName}
        </p>
      </aside>

      <main className='relative flex flex-col'>
        <div className='space-y-2 p-4 sm:p-8 lg:hidden'>
          {brand}
          <p className='text-muted-foreground text-sm'>
            {t('One API, all mainstream models')}
          </p>
        </div>
        <div className='flex flex-1 items-center justify-center px-4 pb-10 sm:px-8 lg:py-10'>
          <div className='bg-background w-full max-w-[460px] space-y-2 rounded-2xl border p-6 shadow-xl shadow-black/5 sm:p-10'>
            {children}
          </div>
        </div>
      </main>
    </div>
  )
}
