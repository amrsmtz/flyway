class CreateAgentAnswers < ActiveRecord::Migration[8.1]
  def change
    # Every answer the agent gave, with what it was built from. It serves as
    # a cache, as the source of the evidence pages, and as an audit trail.
    create_table :agent_answers do |t|
      t.string :question, null: false
      # Lower-cased question plus the day it was asked; identical questions
      # on the same day reuse the answer while it is fresh.
      t.string :question_key, null: false
      # answered, cannot_answer or failed.
      t.string :status, null: false
      t.jsonb :answer, null: false, default: {}
      t.jsonb :tool_results, null: false, default: []
      t.jsonb :evidence, null: false, default: []
      t.string :confidence
      t.jsonb :confidence_reasons, null: false, default: []
      t.jsonb :freshness, null: false, default: []
      t.jsonb :unverified_numbers, null: false, default: []
      t.string :model
      t.integer :duration_ms
      t.string :error
      t.timestamps
    end
    add_index :agent_answers, [ :question_key, :created_at ]
  end
end
