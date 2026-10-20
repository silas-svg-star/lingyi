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
import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Clock, Loader2, Play, Sparkles } from 'lucide-react'
import { useTranslation } from 'react-i18next'

import { SectionPageLayout } from '@/components/layout'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Markdown } from '@/components/ui/markdown'
import { Textarea } from '@/components/ui/textarea'
import { getUserModels, sendChatCompletion } from '@/features/playground/api'
import { DEFAULT_GROUP } from '@/features/playground/constants'
import { cn } from '@/lib/utils'

// Models that can be compared side by side in one run.
export const MAX_COMPARE_MODELS = 4

const SAMPLE_QUESTIONS = [
  'A bat and a ball cost 1.10 in total. The bat costs 1.00 more than the ball. How much does the ball cost? Explain briefly.',
  'If all bloops are razzies and all razzies are lazzies, are all bloops definitely lazzies? Explain briefly.',
  'Which is larger, 9.11 or 9.9? Explain briefly.',
  'A farmer has 17 sheep. All but 9 run away. How many sheep are left?',
]

type CompareResult = {
  status: 'loading' | 'done' | 'error'
  content?: string
  error?: string
  elapsedMs?: number
  completionTokens?: number
}

function errorMessage(error: unknown): string {
  const data = (error as { response?: { data?: unknown } })?.response?.data
  const apiError = (data as { error?: { message?: string } } | undefined)
    ?.error?.message
  if (apiError) return apiError
  return error instanceof Error ? error.message : String(error)
}

export function ModelCompare() {
  const { t } = useTranslation()
  const [selected, setSelected] = useState<string[]>([])
  const [question, setQuestion] = useState('')
  const [results, setResults] = useState<Record<string, CompareResult>>({})

  const { data: models = [], isLoading } = useQuery({
    queryKey: ['model-compare', 'models', DEFAULT_GROUP],
    queryFn: () => getUserModels(DEFAULT_GROUP),
  })

  const running = useMemo(
    () => Object.values(results).some((r) => r.status === 'loading'),
    [results]
  )

  const toggleModel = (model: string) => {
    setSelected((prev) =>
      prev.includes(model)
        ? prev.filter((m) => m !== model)
        : prev.length >= MAX_COMPARE_MODELS
          ? prev
          : [...prev, model]
    )
  }

  const runCompare = () => {
    const prompt = question.trim()
    if (!prompt || selected.length === 0 || running) return
    const order = [...selected]
    setResults(
      Object.fromEntries(order.map((m) => [m, { status: 'loading' as const }]))
    )
    for (const model of order) {
      const started = performance.now()
      sendChatCompletion({
        model,
        group: DEFAULT_GROUP,
        messages: [{ role: 'user', content: prompt }],
        stream: false,
      })
        .then((res) => {
          const message = res.choices?.[0]?.message
          setResults((prev) => ({
            ...prev,
            [model]: {
              status: 'done',
              content: message?.content ?? '',
              elapsedMs: performance.now() - started,
              completionTokens: res.usage?.completion_tokens,
            },
          }))
        })
        .catch((error: unknown) => {
          setResults((prev) => ({
            ...prev,
            [model]: {
              status: 'error',
              error: errorMessage(error),
              elapsedMs: performance.now() - started,
            },
          }))
        })
    }
  }

  const resultModels = Object.keys(results)

  return (
    <SectionPageLayout>
      <SectionPageLayout.Title>{t('Model Compare')}</SectionPageLayout.Title>
      <SectionPageLayout.Content>
        <div className='space-y-6'>
          <Card>
            <CardContent className='space-y-5'>
              <div className='space-y-2'>
                <div className='text-sm font-medium'>
                  {t('Pick up to {{count}} models', {
                    count: MAX_COMPARE_MODELS,
                  })}
                </div>
                <div className='flex flex-wrap gap-2'>
                  {isLoading && (
                    <Loader2 className='text-muted-foreground h-4 w-4 animate-spin' />
                  )}
                  {!isLoading && models.length === 0 && (
                    <span className='text-muted-foreground text-sm'>
                      {t('No models available')}
                    </span>
                  )}
                  {models.map((m) => {
                    const active = selected.includes(m.value)
                    return (
                      <Button
                        key={m.value}
                        type='button'
                        size='sm'
                        variant={active ? 'default' : 'outline'}
                        aria-pressed={active}
                        onClick={() => toggleModel(m.value)}
                      >
                        {m.label}
                      </Button>
                    )
                  })}
                </div>
              </div>

              <div className='space-y-2'>
                <div className='text-sm font-medium'>{t('Question')}</div>
                <Textarea
                  value={question}
                  onChange={(e) => setQuestion(e.target.value)}
                  placeholder={t('Type a question, or pick a sample below')}
                  rows={4}
                />
                <div className='flex flex-wrap gap-2'>
                  {SAMPLE_QUESTIONS.map((q) => (
                    <button
                      key={q}
                      type='button'
                      onClick={() => setQuestion(t(q))}
                      className='bg-muted hover:bg-muted/70 text-muted-foreground max-w-full truncate rounded-full px-3 py-1 text-xs'
                    >
                      <Sparkles className='mr-1 inline h-3 w-3' />
                      {t(q)}
                    </button>
                  ))}
                </div>
              </div>

              <div className='flex flex-wrap items-center gap-3'>
                <Button
                  onClick={runCompare}
                  disabled={
                    running || selected.length === 0 || !question.trim()
                  }
                >
                  {running ? (
                    <Loader2 className='h-4 w-4 animate-spin' />
                  ) : (
                    <Play className='h-4 w-4' />
                  )}
                  {t('Start compare')}
                </Button>
                <span className='text-muted-foreground text-xs'>
                  {t('Each model is billed at its normal price.')}
                </span>
              </div>
            </CardContent>
          </Card>

          {resultModels.length > 0 && (
            <div
              className={cn(
                'grid gap-4',
                resultModels.length > 1 && 'md:grid-cols-2',
                resultModels.length > 2 && 'xl:grid-cols-3',
                resultModels.length > 3 && '2xl:grid-cols-4'
              )}
            >
              {resultModels.map((model) => {
                const r = results[model]
                return (
                  <Card key={model} className='min-w-0'>
                    <CardHeader className='flex flex-row flex-wrap items-center justify-between gap-2'>
                      <CardTitle className='text-base'>{model}</CardTitle>
                      {r.elapsedMs !== undefined && (
                        <div className='flex gap-2'>
                          <Badge variant='secondary'>
                            <Clock className='mr-1 h-3 w-3' />
                            {(r.elapsedMs / 1000).toFixed(1)}s
                          </Badge>
                          {r.completionTokens !== undefined && (
                            <Badge variant='outline'>
                              {r.completionTokens} tokens
                            </Badge>
                          )}
                        </div>
                      )}
                    </CardHeader>
                    <CardContent className='text-sm'>
                      {r.status === 'loading' && (
                        <div className='text-muted-foreground flex items-center gap-2'>
                          <Loader2 className='h-4 w-4 animate-spin' />
                          {t('Thinking...')}
                        </div>
                      )}
                      {r.status === 'error' && (
                        <p className='text-destructive break-words'>
                          {r.error}
                        </p>
                      )}
                      {r.status === 'done' && (
                        <Markdown>{r.content ?? ''}</Markdown>
                      )}
                    </CardContent>
                  </Card>
                )
              })}
            </div>
          )}
        </div>
      </SectionPageLayout.Content>
    </SectionPageLayout>
  )
}
