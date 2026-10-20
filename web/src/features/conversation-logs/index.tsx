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

import {
  getConversationLogs,
  getConversationLogUsers,
  type ConversationLog,
} from './api'

const PAGE_SIZE = 20

// Text of the last user message in an OpenAI/Claude style request body, used
// as a one-line preview. Falls back to empty when the body is not JSON.
function lastUserText(request: string): string {
  try {
    const body = JSON.parse(request) as {
      messages?: Array<{ role?: string; content?: unknown }>
      input?: unknown
    }
    const messages = Array.isArray(body.messages) ? body.messages : []
    for (let i = messages.length - 1; i >= 0; i--) {
      if (messages[i]?.role !== 'user') continue
      const content = messages[i].content
      if (typeof content === 'string') return content
      if (Array.isArray(content)) {
        return content
          .map((part: { text?: string }) => part?.text ?? '')
          .join(' ')
      }
    }
    return typeof body.input === 'string' ? body.input : ''
  } catch {
    return ''
  }
}

// Assistant text from a JSON or SSE (stream) chat/responses reply body.
function replyText(response: string): string {
  const fromObject = (o: Record<string, any>): string => {
    const choice = o?.choices?.[0]
    if (choice) return choice.message?.content ?? choice.delta?.content ?? ''
    if (Array.isArray(o?.content)) {
      return o.content.map((p: { text?: string }) => p?.text ?? '').join('')
    }
    if (typeof o?.output_text === 'string') return o.output_text
    return ''
  }
  try {
    return fromObject(JSON.parse(response))
  } catch {
    // Streamed reply: concatenate the text deltas of each data line.
    return response
      .split('\n')
      .filter((line) => line.startsWith('data:'))
      .map((line) => {
        try {
          const o = JSON.parse(line.slice(5).trim())
          if (o?.type === 'response.output_text.delta') return o.delta ?? ''
          if (o?.type === 'content_block_delta') return o.delta?.text ?? ''
          return o?.type ? '' : fromObject(o)
        } catch {
          return ''
        }
      })
      .join('')
  }
}

function Entry({ item }: { item: ConversationLog }) {
  const { t } = useTranslation()
  const question = lastUserText(item.request)
  const preview = question.slice(0, 200)
  const answer = replyText(item.response)
  return (
    <details className='rounded-lg border p-3'>
      <summary className='flex cursor-pointer flex-wrap items-center gap-2 text-sm'>
        <span className='text-muted-foreground'>
          {new Date(item.created_at * 1000).toLocaleString()}
        </span>
        <Badge variant='outline'>{item.username || `#${item.user_id}`}</Badge>
        <Badge variant='secondary'>{item.model_name || item.path}</Badge>
        <span className='text-muted-foreground'>HTTP {item.status_code}</span>
        {preview && (
          <span className='text-foreground/80 w-full truncate text-xs'>
            {preview}
          </span>
        )}
      </summary>
      <div className='mt-3 space-y-3'>
        {(question || answer) && (
          <div className='grid gap-2 md:grid-cols-2'>
            <div className='rounded border p-2'>
              <div className='text-muted-foreground mb-1 text-xs'>
                {t('Question')}
              </div>
              <div className='max-h-60 overflow-auto text-sm whitespace-pre-wrap'>
                {question}
              </div>
            </div>
            <div className='rounded border p-2'>
              <div className='text-muted-foreground mb-1 text-xs'>
                {t('Reply')}
              </div>
              <div className='max-h-60 overflow-auto text-sm whitespace-pre-wrap'>
                {answer}
              </div>
            </div>
          </div>
        )}
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

function AccountButton(props: {
  active: boolean
  label: string
  count?: number
  onClick: () => void
}) {
  return (
    <button
      type='button'
      onClick={props.onClick}
      className={
        'flex shrink-0 items-center justify-between gap-2 rounded-md px-2 py-1.5 text-left text-sm ' +
        (props.active ? 'bg-primary text-primary-foreground' : 'hover:bg-muted')
      }
    >
      <span className='truncate'>{props.label}</span>
      {props.count !== undefined && (
        <span className='text-xs opacity-70'>{props.count}</span>
      )}
    </button>
  )
}

export function ConversationLogs() {
  const { t } = useTranslation()
  const [page, setPage] = useState(1)
  const [keywordInput, setKeywordInput] = useState('')
  const [keyword, setKeyword] = useState('')
  const [accountInput, setAccountInput] = useState('')
  const [account, setAccount] = useState('')
  const [userId, setUserId] = useState(0)
  const options = useSystemOptions()
  const updateOption = useUpdateOption()
  const enabled =
    options.data?.data?.find((o) => o.key === 'ConversationLogEnabled')
      ?.value === 'true'

  const logs = useQuery({
    queryKey: ['conversation-logs', page, keyword, userId],
    queryFn: () =>
      getConversationLogs({
        p: page,
        page_size: PAGE_SIZE,
        keyword,
        user_id: userId || undefined,
      }),
  })
  const users = useQuery({
    queryKey: ['conversation-log-users', account],
    queryFn: () => getConversationLogUsers(account),
  })
  const selectUser = (id: number) => {
    setUserId(id)
    setPage(1)
  }
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

          <div className='grid gap-4 lg:grid-cols-[260px_minmax(0,1fr)]'>
            <aside className='space-y-2 rounded-lg border p-3'>
              <div className='text-sm font-medium'>{t('Accounts')}</div>
              <form
                className='flex gap-2'
                onSubmit={(e) => {
                  e.preventDefault()
                  setAccount(accountInput.trim())
                }}
              >
                <Input
                  value={accountInput}
                  onChange={(e) => setAccountInput(e.target.value)}
                  placeholder={t('Search account')}
                />
                <Button type='submit' variant='outline'>
                  {t('Search')}
                </Button>
              </form>
              <div className='flex max-h-[60vh] gap-1 overflow-auto max-lg:pb-1 lg:flex-col'>
                <AccountButton
                  active={userId === 0}
                  label={t('All accounts')}
                  onClick={() => selectUser(0)}
                />
                {users.data?.map((u) => (
                  <AccountButton
                    key={u.user_id}
                    active={userId === u.user_id}
                    label={u.username || `#${u.user_id}`}
                    count={u.count}
                    onClick={() => selectUser(u.user_id)}
                  />
                ))}
                {users.data && users.data.length === 0 && (
                  <div className='text-muted-foreground px-2 py-4 text-xs'>
                    {t('No matching accounts')}
                  </div>
                )}
              </div>
            </aside>

            <div className='min-w-0 space-y-4'>
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
          </div>
        </div>
      </SectionPageLayout.Content>
    </SectionPageLayout>
  )
}
