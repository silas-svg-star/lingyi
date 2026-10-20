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
import { useQuery } from '@tanstack/react-query'
import { useState } from 'react'
import { useTranslation } from 'react-i18next'

import { SectionPageLayout } from '@/components/layout'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Switch } from '@/components/ui/switch'
import { useSystemOptions } from '@/features/system-settings/hooks/use-system-options'
import { useUpdateOption } from '@/features/system-settings/hooks/use-update-option'

import { getConversationLogs, type ConversationLog } from './api'

const PAGE_SIZE = 20

function Entry({ item }: { item: ConversationLog }) {
  const { t } = useTranslation()
  return (
    <details className='rounded-lg border p-3'>
      <summary className='flex cursor-pointer flex-wrap items-center gap-2 text-sm'>
        <span className='text-muted-foreground'>
          {new Date(item.created_at * 1000).toLocaleString()}
        </span>
        <Badge variant='outline'>{item.username || `#${item.user_id}`}</Badge>
        <Badge variant='secondary'>{item.model_name || item.path}</Badge>
        <span className='text-muted-foreground'>HTTP {item.status_code}</span>
      </summary>
      <div className='mt-3 space-y-3'>
        <div>
          <div className='text-muted-foreground mb-1 text-xs'>
            {t('Request')}
          </div>
          <pre className='bg-muted max-h-80 overflow-auto rounded p-2 text-xs break-all whitespace-pre-wrap'>
            {item.request}
          </pre>
        </div>
        <div>
          <div className='text-muted-foreground mb-1 text-xs'>
            {t('Response')}
          </div>
          <pre className='bg-muted max-h-80 overflow-auto rounded p-2 text-xs break-all whitespace-pre-wrap'>
            {item.response}
          </pre>
        </div>
      </div>
    </details>
  )
}

export function ConversationLogs() {
  const { t } = useTranslation()
  const [page, setPage] = useState(1)
  const [keywordInput, setKeywordInput] = useState('')
  const [keyword, setKeyword] = useState('')
  const options = useSystemOptions()
  const updateOption = useUpdateOption()
  const enabled =
    options.data?.data?.find((o) => o.key === 'ConversationLogEnabled')
      ?.value === 'true'

  const logs = useQuery({
    queryKey: ['conversation-logs', page, keyword],
    queryFn: () =>
      getConversationLogs({ p: page, page_size: PAGE_SIZE, keyword }),
  })
  const total = logs.data?.total ?? 0
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  return (
    <SectionPageLayout>
      <SectionPageLayout.Title>
        {t('Conversation Logs')}
      </SectionPageLayout.Title>
      <SectionPageLayout.Content>
        <div className='space-y-4'>
          <div className='flex items-start justify-between gap-4 rounded-lg border p-4'>
            <div className='space-y-1 text-sm'>
              <div className='font-medium'>
                {t('Save conversation content')}
              </div>
              <div className='text-muted-foreground'>
                {t(
                  'Off by default. When on, prompts and replies are stored, visible to admins only, and deleted after 7 days. The sign-in and sign-up pages show a notice while it is on.'
                )}
              </div>
            </div>
            <Switch
              checked={enabled}
              disabled={options.isLoading || updateOption.isPending}
              onCheckedChange={(v) =>
                updateOption.mutate({
                  key: 'ConversationLogEnabled',
                  value: v,
                })
              }
            />
          </div>

          <form
            className='flex gap-2'
            onSubmit={(e) => {
              e.preventDefault()
              setPage(1)
              setKeyword(keywordInput.trim())
            }}
          >
            <Input
              value={keywordInput}
              onChange={(e) => setKeywordInput(e.target.value)}
              placeholder={t('Search conversation content')}
            />
            <Button type='submit'>{t('Search')}</Button>
          </form>

          <div className='space-y-2'>
            {logs.data?.items?.map((item) => (
              <Entry key={item.id} item={item} />
            ))}
            {logs.data && logs.data.items?.length === 0 && (
              <div className='text-muted-foreground py-8 text-center text-sm'>
                {t('No conversations saved')}
              </div>
            )}
          </div>

          <div className='flex items-center justify-between text-sm'>
            <span className='text-muted-foreground'>
              {page} / {pages} ({total})
            </span>
            <div className='flex gap-2'>
              <Button
                variant='outline'
                disabled={page <= 1}
                onClick={() => setPage((p) => p - 1)}
              >
                {t('Previous')}
              </Button>
              <Button
                variant='outline'
                disabled={page >= pages}
                onClick={() => setPage((p) => p + 1)}
              >
                {t('Next')}
              </Button>
            </div>
          </div>
        </div>
      </SectionPageLayout.Content>
    </SectionPageLayout>
  )
}
