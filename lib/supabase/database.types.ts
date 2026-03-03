export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.1"
  }
  analytics: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      v_expenses_cost_center_daily: {
        Row: {
          amount: number | null
          cost_center_code: string | null
          day: string | null
          org_id: string | null
        }
        Relationships: []
      }
      v_expenses_daily: {
        Row: {
          amount: number | null
          day: string | null
          expense_rows: number | null
          org_id: string | null
          tax_amount: number | null
          total_amount: number | null
        }
        Relationships: []
      }
      v_expenses_enriched: {
        Row: {
          amount: number | null
          branch_id: string | null
          category: string | null
          cost_center_code: string | null
          currency: string | null
          day: string | null
          org_id: string | null
          payment_method: string | null
          reference_number: string | null
          tax_amount: number | null
          total_amount: number | null
          vendor: string | null
        }
        Insert: {
          amount?: number | null
          branch_id?: string | null
          category?: string | null
          cost_center_code?: string | null
          currency?: string | null
          day?: string | null
          org_id?: string | null
          payment_method?: string | null
          reference_number?: string | null
          tax_amount?: never
          total_amount?: never
          vendor?: string | null
        }
        Update: {
          amount?: number | null
          branch_id?: string | null
          category?: string | null
          cost_center_code?: string | null
          currency?: string | null
          day?: string | null
          org_id?: string | null
          payment_method?: string | null
          reference_number?: string | null
          tax_amount?: never
          total_amount?: never
          vendor?: string | null
        }
        Relationships: []
      }
      v_kpi_daily: {
        Row: {
          day: string | null
          expenses: number | null
          gross_profit: number | null
          net_sales: number | null
          operating_profit: number | null
          org_id: string | null
        }
        Relationships: []
      }
      v_kpi_daily_sales: {
        Row: {
          day: string | null
          invoices: number | null
          net_sales: number | null
          org_id: string | null
          tax_amount: number | null
          total_amount: number | null
        }
        Relationships: []
      }
      v_sales_daily: {
        Row: {
          day: string | null
          invoices: number | null
          net_sales: number | null
          org_id: string | null
          tax_amount: number | null
          total_amount: number | null
        }
        Relationships: []
      }
      v_sales_line_financials: {
        Row: {
          branch_id: string | null
          category: string | null
          channel: string | null
          currency: string | null
          day: string | null
          discount_rate: number | null
          external_invoice_number: string | null
          invoice_type: string | null
          line_number: number | null
          net_sales: number | null
          org_id: string | null
          payment_method: string | null
          product_name: string | null
          quantity: number | null
          sku: string | null
          tax_amount: number | null
          total_amount: number | null
          unit_price: number | null
          vat_rate: number | null
        }
        Relationships: []
      }
    }
    Functions: {
      [_ in never]: never
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      branches: {
        Row: {
          code: string | null
          created_at: string
          id: string
          is_default: boolean
          name: string
          org_id: string
        }
        Insert: {
          code?: string | null
          created_at?: string
          id?: string
          is_default?: boolean
          name: string
          org_id: string
        }
        Update: {
          code?: string | null
          created_at?: string
          id?: string
          is_default?: boolean
          name?: string
          org_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "branches_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
      cost_centers: {
        Row: {
          code: string
          created_at: string
          id: string
          is_system: boolean
          name: string
          org_id: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          is_system?: boolean
          name: string
          org_id: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          is_system?: boolean
          name?: string
          org_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "cost_centers_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
      expense_allocation_audit: {
        Row: {
          changed_by: string | null
          created_at: string
          expense_id: string
          id: string
          new_allocations: Json
          org_id: string
          previous_allocations: Json
        }
        Insert: {
          changed_by?: string | null
          created_at?: string
          expense_id: string
          id?: string
          new_allocations?: Json
          org_id: string
          previous_allocations?: Json
        }
        Update: {
          changed_by?: string | null
          created_at?: string
          expense_id?: string
          id?: string
          new_allocations?: Json
          org_id?: string
          previous_allocations?: Json
        }
        Relationships: [
          {
            foreignKeyName: "expense_allocation_audit_expense_id_fkey"
            columns: ["expense_id"]
            isOneToOne: false
            referencedRelation: "expenses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expense_allocation_audit_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
      expense_allocations: {
        Row: {
          amount: number
          cost_center_code: string
          created_at: string
          created_by: string | null
          expense_id: string
          id: string
          org_id: string
          updated_at: string
        }
        Insert: {
          amount: number
          cost_center_code: string
          created_at?: string
          created_by?: string | null
          expense_id: string
          id?: string
          org_id: string
          updated_at?: string
        }
        Update: {
          amount?: number
          cost_center_code?: string
          created_at?: string
          created_by?: string | null
          expense_id?: string
          id?: string
          org_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "expense_allocations_expense_id_fkey"
            columns: ["expense_id"]
            isOneToOne: false
            referencedRelation: "expenses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expense_allocations_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
      expenses: {
        Row: {
          amount: number
          branch_id: string | null
          category: string
          cost_center_code: string | null
          created_at: string
          currency: string | null
          expense_date: string
          id: string
          notes: string | null
          org_id: string
          payment_method: string | null
          reference_number: string | null
          source_hash: string
          source_import_job_id: string | null
          tax_amount: number | null
          total_amount: number | null
          updated_at: string
          vat_rate: number | null
          vendor: string | null
        }
        Insert: {
          amount: number
          branch_id?: string | null
          category: string
          cost_center_code?: string | null
          created_at?: string
          currency?: string | null
          expense_date: string
          id?: string
          notes?: string | null
          org_id: string
          payment_method?: string | null
          reference_number?: string | null
          source_hash: string
          source_import_job_id?: string | null
          tax_amount?: number | null
          total_amount?: number | null
          updated_at?: string
          vat_rate?: number | null
          vendor?: string | null
        }
        Update: {
          amount?: number
          branch_id?: string | null
          category?: string
          cost_center_code?: string | null
          created_at?: string
          currency?: string | null
          expense_date?: string
          id?: string
          notes?: string | null
          org_id?: string
          payment_method?: string | null
          reference_number?: string | null
          source_hash?: string
          source_import_job_id?: string | null
          tax_amount?: number | null
          total_amount?: number | null
          updated_at?: string
          vat_rate?: number | null
          vendor?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "expenses_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_source_import_job_id_fkey"
            columns: ["source_import_job_id"]
            isOneToOne: false
            referencedRelation: "import_jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      forecast_model_configs: {
        Row: {
          config: Json
          engine: string
          granularity: string
          target: string
          updated_at: string
        }
        Insert: {
          config?: Json
          engine: string
          granularity: string
          target?: string
          updated_at?: string
        }
        Update: {
          config?: Json
          engine?: string
          granularity?: string
          target?: string
          updated_at?: string
        }
        Relationships: []
      }
      forecast_outputs: {
        Row: {
          created_at: string
          day: string
          engine: string
          id: number
          org_id: string
          p50_net_sales: number
          p80_high: number
          p80_low: number
          p95_high: number
          p95_low: number
          run_id: string
          visibility: string
        }
        Insert: {
          created_at?: string
          day: string
          engine?: string
          id?: number
          org_id: string
          p50_net_sales: number
          p80_high: number
          p80_low: number
          p95_high: number
          p95_low: number
          run_id: string
          visibility?: string
        }
        Update: {
          created_at?: string
          day?: string
          engine?: string
          id?: number
          org_id?: string
          p50_net_sales?: number
          p80_high?: number
          p80_low?: number
          p95_high?: number
          p95_low?: number
          run_id?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "forecast_outputs_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "forecast_outputs_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "forecast_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      forecast_runs: {
        Row: {
          anchor_date: string
          branch_id: string | null
          created_at: string
          created_by: string
          engine: string
          finished_at: string | null
          history_days: number
          horizon_days: number
          id: string
          message: string | null
          metrics: Json
          model: string
          org_id: string
          params: Json
          started_at: string | null
          status: string
          visibility: string
        }
        Insert: {
          anchor_date: string
          branch_id?: string | null
          created_at?: string
          created_by: string
          engine?: string
          finished_at?: string | null
          history_days?: number
          horizon_days?: number
          id?: string
          message?: string | null
          metrics?: Json
          model?: string
          org_id: string
          params?: Json
          started_at?: string | null
          status: string
          visibility?: string
        }
        Update: {
          anchor_date?: string
          branch_id?: string | null
          created_at?: string
          created_by?: string
          engine?: string
          finished_at?: string | null
          history_days?: number
          horizon_days?: number
          id?: string
          message?: string | null
          metrics?: Json
          model?: string
          org_id?: string
          params?: Json
          started_at?: string | null
          status?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "forecast_runs_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
      import_contract_fields: {
        Row: {
          canonical_key: string
          data_type: string
          display_name: string
          entity_type: Database["public"]["Enums"]["import_entity"]
          is_required: boolean
          ordinal: number
        }
        Insert: {
          canonical_key: string
          data_type: string
          display_name: string
          entity_type: Database["public"]["Enums"]["import_entity"]
          is_required?: boolean
          ordinal?: number
        }
        Update: {
          canonical_key?: string
          data_type?: string
          display_name?: string
          entity_type?: Database["public"]["Enums"]["import_entity"]
          is_required?: boolean
          ordinal?: number
        }
        Relationships: []
      }
      import_job_rows: {
        Row: {
          created_at: string
          errors: Json
          id: number
          is_valid: boolean
          job_id: string
          parsed: Json
          raw: Json
          row_number: number
        }
        Insert: {
          created_at?: string
          errors?: Json
          id?: number
          is_valid?: boolean
          job_id: string
          parsed?: Json
          raw: Json
          row_number: number
        }
        Update: {
          created_at?: string
          errors?: Json
          id?: number
          is_valid?: boolean
          job_id?: string
          parsed?: Json
          raw?: Json
          row_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "import_job_rows_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "import_jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      import_jobs: {
        Row: {
          content_type: string | null
          created_at: string
          created_by: string
          entity_type: Database["public"]["Enums"]["import_entity"]
          file_size: number | null
          id: string
          metadata: Json
          org_id: string
          original_filename: string
          status: Database["public"]["Enums"]["import_job_status"]
          storage_bucket: string
          storage_path: string
          summary: Json
          updated_at: string
        }
        Insert: {
          content_type?: string | null
          created_at?: string
          created_by: string
          entity_type: Database["public"]["Enums"]["import_entity"]
          file_size?: number | null
          id?: string
          metadata?: Json
          org_id: string
          original_filename: string
          status?: Database["public"]["Enums"]["import_job_status"]
          storage_bucket?: string
          storage_path: string
          summary?: Json
          updated_at?: string
        }
        Update: {
          content_type?: string | null
          created_at?: string
          created_by?: string
          entity_type?: Database["public"]["Enums"]["import_entity"]
          file_size?: number | null
          id?: string
          metadata?: Json
          org_id?: string
          original_filename?: string
          status?: Database["public"]["Enums"]["import_job_status"]
          storage_bucket?: string
          storage_path?: string
          summary?: Json
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "import_jobs_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
      ingredient_receipts: {
        Row: {
          created_at: string
          currency: string | null
          id: string
          ingredient_id: string
          org_id: string
          qty_base: number
          receipt_date: string
          total_cost: number
          vendor: string | null
        }
        Insert: {
          created_at?: string
          currency?: string | null
          id?: string
          ingredient_id: string
          org_id: string
          qty_base: number
          receipt_date: string
          total_cost: number
          vendor?: string | null
        }
        Update: {
          created_at?: string
          currency?: string | null
          id?: string
          ingredient_id?: string
          org_id?: string
          qty_base?: number
          receipt_date?: string
          total_cost?: number
          vendor?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ingredient_receipts_ingredient_id_fkey"
            columns: ["ingredient_id"]
            isOneToOne: false
            referencedRelation: "ingredients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingredient_receipts_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
      ingredients: {
        Row: {
          active: boolean
          base_uom: string
          created_at: string
          id: string
          ingredient_code: string
          kind: string
          name: string
          org_id: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          base_uom: string
          created_at?: string
          id?: string
          ingredient_code: string
          kind: string
          name: string
          org_id: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          base_uom?: string
          created_at?: string
          id?: string
          ingredient_code?: string
          kind?: string
          name?: string
          org_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ingredients_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
      labor_entries: {
        Row: {
          branch_id: string
          cost: number
          created_at: string
          currency: string | null
          employee_id: string
          employee_name: string | null
          hourly_rate: number
          hours: number
          id: string
          org_id: string
          role: string
          source_import_job_id: string | null
          updated_at: string
          work_date: string
        }
        Insert: {
          branch_id: string
          cost: number
          created_at?: string
          currency?: string | null
          employee_id: string
          employee_name?: string | null
          hourly_rate: number
          hours: number
          id?: string
          org_id: string
          role: string
          source_import_job_id?: string | null
          updated_at?: string
          work_date: string
        }
        Update: {
          branch_id?: string
          cost?: number
          created_at?: string
          currency?: string | null
          employee_id?: string
          employee_name?: string | null
          hourly_rate?: number
          hours?: number
          id?: string
          org_id?: string
          role?: string
          source_import_job_id?: string | null
          updated_at?: string
          work_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "labor_entries_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "labor_entries_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "labor_entries_source_import_job_id_fkey"
            columns: ["source_import_job_id"]
            isOneToOne: false
            referencedRelation: "import_jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      labor_rates: {
        Row: {
          burden_pct: number
          created_at: string
          effective_start: string
          hourly_rate: number
          id: string
          org_id: string
          role_code: string
        }
        Insert: {
          burden_pct?: number
          created_at?: string
          effective_start: string
          hourly_rate: number
          id?: string
          org_id: string
          role_code: string
        }
        Update: {
          burden_pct?: number
          created_at?: string
          effective_start?: string
          hourly_rate?: number
          id?: string
          org_id?: string
          role_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "labor_rates_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "labor_rates_role_code_fkey"
            columns: ["role_code"]
            isOneToOne: false
            referencedRelation: "labor_roles"
            referencedColumns: ["role_code"]
          },
        ]
      }
      labor_roles: {
        Row: {
          name: string
          role_code: string
        }
        Insert: {
          name: string
          role_code: string
        }
        Update: {
          name?: string
          role_code?: string
        }
        Relationships: []
      }
      org_cost_engine_settings: {
        Row: {
          created_at: string
          org_id: string
          overhead_codes: string[]
          treat_unallocated_as_overhead: boolean
          wac_days: number
        }
        Insert: {
          created_at?: string
          org_id: string
          overhead_codes?: string[]
          treat_unallocated_as_overhead?: boolean
          wac_days?: number
        }
        Update: {
          created_at?: string
          org_id?: string
          overhead_codes?: string[]
          treat_unallocated_as_overhead?: boolean
          wac_days?: number
        }
        Relationships: [
          {
            foreignKeyName: "org_cost_engine_settings_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: true
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
      org_members: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          created_at: string
          id: string
          org_id: string
          role: Database["public"]["Enums"]["org_role"]
          status: string
          user_id: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          id?: string
          org_id: string
          role?: Database["public"]["Enums"]["org_role"]
          status?: string
          user_id: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          id?: string
          org_id?: string
          role?: Database["public"]["Enums"]["org_role"]
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "org_members_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
      orgs: {
        Row: {
          created_at: string
          created_by: string
          id: string
          is_listed: boolean
          name: string
          subscription_tier_code: string
          support_email: string | null
        }
        Insert: {
          created_at?: string
          created_by: string
          id?: string
          is_listed?: boolean
          name: string
          subscription_tier_code?: string
          support_email?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          is_listed?: boolean
          name?: string
          subscription_tier_code?: string
          support_email?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "orgs_subscription_tier_fkey"
            columns: ["subscription_tier_code"]
            isOneToOne: false
            referencedRelation: "subscription_tiers"
            referencedColumns: ["tier_code"]
          },
        ]
      }
      platform_admins: {
        Row: {
          created_at: string
          email: string
          user_id: string
        }
        Insert: {
          created_at?: string
          email: string
          user_id: string
        }
        Update: {
          created_at?: string
          email?: string
          user_id?: string
        }
        Relationships: []
      }
      platform_audit_log: {
        Row: {
          action: string
          actor_email: string | null
          actor_user_id: string | null
          entity: string
          entity_id: string | null
          id: number
          meta: Json
          occurred_at: string
          org_id: string | null
        }
        Insert: {
          action: string
          actor_email?: string | null
          actor_user_id?: string | null
          entity: string
          entity_id?: string | null
          id?: number
          meta?: Json
          occurred_at?: string
          org_id?: string | null
        }
        Update: {
          action?: string
          actor_email?: string | null
          actor_user_id?: string | null
          entity?: string
          entity_id?: string | null
          id?: number
          meta?: Json
          occurred_at?: string
          org_id?: string | null
        }
        Relationships: []
      }
      platform_role_mappings: {
        Row: {
          kind: string
          role_label: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          kind: string
          role_label: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          kind?: string
          role_label?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      platform_settings: {
        Row: {
          created_at: string
          id: number
          support_email: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: number
          support_email: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: number
          support_email?: string
          updated_at?: string
        }
        Relationships: []
      }
      product_labor_specs: {
        Row: {
          created_at: string
          id: string
          org_id: string
          role_code: string
          seconds_per_unit: number
          sku: string
        }
        Insert: {
          created_at?: string
          id?: string
          org_id: string
          role_code: string
          seconds_per_unit: number
          sku: string
        }
        Update: {
          created_at?: string
          id?: string
          org_id?: string
          role_code?: string
          seconds_per_unit?: number
          sku?: string
        }
        Relationships: [
          {
            foreignKeyName: "product_labor_specs_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_labor_specs_role_code_fkey"
            columns: ["role_code"]
            isOneToOne: false
            referencedRelation: "labor_roles"
            referencedColumns: ["role_code"]
          },
        ]
      }
      product_packaging_items: {
        Row: {
          created_at: string
          id: string
          ingredient_id: string
          org_id: string
          qty: number
          sku: string
          uom: string
        }
        Insert: {
          created_at?: string
          id?: string
          ingredient_id: string
          org_id: string
          qty: number
          sku: string
          uom: string
        }
        Update: {
          created_at?: string
          id?: string
          ingredient_id?: string
          org_id?: string
          qty?: number
          sku?: string
          uom?: string
        }
        Relationships: [
          {
            foreignKeyName: "product_packaging_items_ingredient_id_fkey"
            columns: ["ingredient_id"]
            isOneToOne: false
            referencedRelation: "ingredients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_packaging_items_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
      products: {
        Row: {
          active: boolean
          category: string | null
          created_at: string
          currency: string | null
          default_price: number | null
          id: string
          org_id: string
          product_name: string
          sku: string
          unit_cost: number | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          category?: string | null
          created_at?: string
          currency?: string | null
          default_price?: number | null
          id?: string
          org_id: string
          product_name: string
          sku: string
          unit_cost?: number | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          category?: string | null
          created_at?: string
          currency?: string | null
          default_price?: number | null
          id?: string
          org_id?: string
          product_name?: string
          sku?: string
          unit_cost?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "products_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string
          email: string | null
          full_name: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          email?: string | null
          full_name?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          email?: string | null
          full_name?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      recipe_items: {
        Row: {
          created_at: string
          id: string
          ingredient_id: string
          loss_pct: number
          qty: number
          recipe_version_id: string
          uom: string
        }
        Insert: {
          created_at?: string
          id?: string
          ingredient_id: string
          loss_pct?: number
          qty: number
          recipe_version_id: string
          uom: string
        }
        Update: {
          created_at?: string
          id?: string
          ingredient_id?: string
          loss_pct?: number
          qty?: number
          recipe_version_id?: string
          uom?: string
        }
        Relationships: [
          {
            foreignKeyName: "recipe_items_ingredient_id_fkey"
            columns: ["ingredient_id"]
            isOneToOne: false
            referencedRelation: "ingredients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recipe_items_recipe_version_id_fkey"
            columns: ["recipe_version_id"]
            isOneToOne: false
            referencedRelation: "recipe_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      recipe_versions: {
        Row: {
          created_at: string
          effective_end: string | null
          effective_start: string
          id: string
          notes: string | null
          org_id: string
          sku: string
          yield_qty: number
        }
        Insert: {
          created_at?: string
          effective_end?: string | null
          effective_start: string
          id?: string
          notes?: string | null
          org_id: string
          sku: string
          yield_qty: number
        }
        Update: {
          created_at?: string
          effective_end?: string | null
          effective_start?: string
          id?: string
          notes?: string | null
          org_id?: string
          sku?: string
          yield_qty?: number
        }
        Relationships: [
          {
            foreignKeyName: "recipe_versions_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_invoices: {
        Row: {
          branch_id: string | null
          channel: string | null
          created_at: string
          currency: string | null
          external_invoice_number: string
          id: string
          invoice_date: string
          invoice_type: string | null
          org_id: string
          payment_method: string | null
          source_import_job_id: string | null
          updated_at: string
        }
        Insert: {
          branch_id?: string | null
          channel?: string | null
          created_at?: string
          currency?: string | null
          external_invoice_number: string
          id?: string
          invoice_date: string
          invoice_type?: string | null
          org_id: string
          payment_method?: string | null
          source_import_job_id?: string | null
          updated_at?: string
        }
        Update: {
          branch_id?: string | null
          channel?: string | null
          created_at?: string
          currency?: string | null
          external_invoice_number?: string
          id?: string
          invoice_date?: string
          invoice_type?: string | null
          org_id?: string
          payment_method?: string | null
          source_import_job_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "sales_invoices_branch_id_fkey"
            columns: ["branch_id"]
            isOneToOne: false
            referencedRelation: "branches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_invoices_source_import_job_id_fkey"
            columns: ["source_import_job_id"]
            isOneToOne: false
            referencedRelation: "import_jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_items: {
        Row: {
          category: string | null
          cogs_labor: number
          cogs_material: number
          cogs_missing: Json
          cogs_model: string
          cogs_overhead: number
          cogs_packaging: number
          cogs_status: string
          cogs_total: number
          created_at: string
          currency: string | null
          discount_rate: number | null
          id: string
          invoice_id: string
          line_number: number
          net_sales: number
          org_id: string
          product_name: string
          quantity: number
          recipe_version_id: string | null
          sku: string | null
          source_import_job_id: string | null
          tax_amount: number | null
          total_amount: number | null
          unit_price: number | null
          updated_at: string
          vat_rate: number | null
        }
        Insert: {
          category?: string | null
          cogs_labor?: number
          cogs_material?: number
          cogs_missing?: Json
          cogs_model?: string
          cogs_overhead?: number
          cogs_packaging?: number
          cogs_status?: string
          cogs_total?: number
          created_at?: string
          currency?: string | null
          discount_rate?: number | null
          id?: string
          invoice_id: string
          line_number: number
          net_sales: number
          org_id: string
          product_name: string
          quantity?: number
          recipe_version_id?: string | null
          sku?: string | null
          source_import_job_id?: string | null
          tax_amount?: number | null
          total_amount?: number | null
          unit_price?: number | null
          updated_at?: string
          vat_rate?: number | null
        }
        Update: {
          category?: string | null
          cogs_labor?: number
          cogs_material?: number
          cogs_missing?: Json
          cogs_model?: string
          cogs_overhead?: number
          cogs_packaging?: number
          cogs_status?: string
          cogs_total?: number
          created_at?: string
          currency?: string | null
          discount_rate?: number | null
          id?: string
          invoice_id?: string
          line_number?: number
          net_sales?: number
          org_id?: string
          product_name?: string
          quantity?: number
          recipe_version_id?: string | null
          sku?: string | null
          source_import_job_id?: string | null
          tax_amount?: number | null
          total_amount?: number | null
          unit_price?: number | null
          updated_at?: string
          vat_rate?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_items_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "sales_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_items_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_items_recipe_version_id_fkey"
            columns: ["recipe_version_id"]
            isOneToOne: false
            referencedRelation: "recipe_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_items_source_import_job_id_fkey"
            columns: ["source_import_job_id"]
            isOneToOne: false
            referencedRelation: "import_jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      subscription_tiers: {
        Row: {
          created_at: string
          forecast_enabled: boolean
          global_benchmark_enabled: boolean
          max_benchmark_plots: number
          max_branches: number
          max_forecast_history_days: number
          max_forecast_horizon_days: number
          max_forecast_runs_per_day: number
          name: string
          paid_forecast_enabled: boolean
          tier_code: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          forecast_enabled?: boolean
          global_benchmark_enabled?: boolean
          max_benchmark_plots: number
          max_branches: number
          max_forecast_history_days?: number
          max_forecast_horizon_days?: number
          max_forecast_runs_per_day?: number
          name: string
          paid_forecast_enabled?: boolean
          tier_code: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          forecast_enabled?: boolean
          global_benchmark_enabled?: boolean
          max_benchmark_plots?: number
          max_branches?: number
          max_forecast_history_days?: number
          max_forecast_horizon_days?: number
          max_forecast_runs_per_day?: number
          name?: string
          paid_forecast_enabled?: boolean
          tier_code?: string
          updated_at?: string
        }
        Relationships: []
      }
      user_daily_usage: {
        Row: {
          active_seconds: number
          day: string
          last_at: string
          org_id: string
          sessions: number
          user_id: string
        }
        Insert: {
          active_seconds?: number
          day: string
          last_at?: string
          org_id: string
          sessions?: number
          user_id: string
        }
        Update: {
          active_seconds?: number
          day?: string
          last_at?: string
          org_id?: string
          sessions?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_daily_usage_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
      user_page_views_daily: {
        Row: {
          day: string
          last_at: string
          org_id: string
          path: string
          user_id: string
          views: number
        }
        Insert: {
          day: string
          last_at?: string
          org_id: string
          path: string
          user_id: string
          views?: number
        }
        Update: {
          day?: string
          last_at?: string
          org_id?: string
          path?: string
          user_id?: string
          views?: number
        }
        Relationships: [
          {
            foreignKeyName: "user_page_views_daily_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
      user_sessions: {
        Row: {
          created_at: string
          end_reason: string | null
          ended_at: string | null
          id: string
          last_seen_at: string
          org_id: string
          started_at: string
          user_agent: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          end_reason?: string | null
          ended_at?: string | null
          id?: string
          last_seen_at?: string
          org_id: string
          started_at?: string
          user_agent?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          end_reason?: string | null
          ended_at?: string | null
          id?: string
          last_seen_at?: string
          org_id?: string
          started_at?: string
          user_agent?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_sessions_org_id_fkey"
            columns: ["org_id"]
            isOneToOne: false
            referencedRelation: "orgs"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      allocate_expense_to_cost_centers: {
        Args: { p_allocations: Json; p_expense_id: string }
        Returns: Json
      }
      apply_unit_economics_to_sales_job: {
        Args: { p_job_id: string; p_wac_days?: number }
        Returns: Json
      }
      auto_allocate_expense: { Args: { p_expense_id: string }; Returns: Json }
      auto_allocate_expenses_for_job: {
        Args: { p_job_id: string }
        Returns: Json
      }
      compute_unit_cogs: {
        Args: {
          p_as_of: string
          p_org_id: string
          p_sku: string
          p_wac_days?: number
        }
        Returns: Json
      }
      create_forecast_run: {
        Args: {
          p_branch_id?: string
          p_engine?: string
          p_history_days?: number
          p_horizon_days?: number
          p_org_id: string
        }
        Returns: {
          anchor_date: string
          branch_id: string | null
          created_at: string
          created_by: string
          engine: string
          finished_at: string | null
          history_days: number
          horizon_days: number
          id: string
          message: string | null
          metrics: Json
          model: string
          org_id: string
          params: Json
          started_at: string | null
          status: string
          visibility: string
        }
        SetofOptions: {
          from: "*"
          to: "forecast_runs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_import_job: {
        Args: {
          p_content_type: string
          p_entity_type: Database["public"]["Enums"]["import_entity"]
          p_file_size: number
          p_job_id: string
          p_metadata: Json
          p_org_id: string
          p_original_filename: string
          p_storage_path: string
        }
        Returns: {
          content_type: string | null
          created_at: string
          created_by: string
          entity_type: Database["public"]["Enums"]["import_entity"]
          file_size: number | null
          id: string
          metadata: Json
          org_id: string
          original_filename: string
          status: Database["public"]["Enums"]["import_job_status"]
          storage_bucket: string
          storage_path: string
          summary: Json
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "import_jobs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_org: { Args: { p_name: string }; Returns: string }
      default_org_member_role: {
        Args: never
        Returns: Database["public"]["Enums"]["org_role"]
      }
      expense_source_hash: { Args: { p: Json }; Returns: string }
      get_benchmark_points: {
        Args: { p_days?: number; p_org_id: string }
        Returns: {
          branch_id: string
          label: string
          n: number
          plot_id: string
          plot_title: string
          series: string
          x: number
          x_label: string
          y: number
          y_label: string
        }[]
      }
      get_benchmark_points_core: {
        Args: { p_days?: number; p_org_id: string }
        Returns: {
          branch_id: string
          label: string
          n: number
          plot_id: string
          plot_title: string
          series: string
          x: number
          x_label: string
          y: number
          y_label: string
        }[]
      }
      get_exec_daily: {
        Args: { p_branch_id?: string; p_days?: number; p_org_id: string }
        Returns: {
          cogs_total: number
          day: string
          expenses_total: number
          gross_margin: number
          gross_profit: number
          invoices: number
          labor_total: number
          net_profit: number
          net_sales: number
        }[]
      }
      get_exec_kpis:
        | {
            Args: {
              p_branch_id?: string
              p_cogs_mode?: string
              p_days?: number
              p_org_id: string
            }
            Returns: Json
          }
        | {
            Args: { p_cogs_mode?: string; p_days?: number; p_org_id: string }
            Returns: Json
          }
      get_exec_monthly:
        | {
            Args: {
              p_branch_id?: string
              p_cogs_mode?: string
              p_months?: number
              p_org_id: string
            }
            Returns: {
              gross_profit: number
              month: string
              net_sales: number
            }[]
          }
        | {
            Args: { p_cogs_mode?: string; p_months?: number; p_org_id: string }
            Returns: {
              gross_profit: number
              month: string
              net_sales: number
            }[]
          }
      get_expense_allocations: {
        Args: { p_expense_id: string }
        Returns: {
          amount: number
          cost_center_code: string
        }[]
      }
      get_expense_category_mix: {
        Args: {
          p_branch_id?: string
          p_days?: number
          p_limit?: number
          p_org_id: string
        }
        Returns: {
          amount: number
          category: string
        }[]
      }
      get_expenses_cost_center_daily: {
        Args: { p_limit?: number; p_org_id: string }
        Returns: {
          amount: number
          cost_center_code: string
          day: string
        }[]
      }
      get_expenses_daily:
        | {
            Args: { p_limit?: number; p_org_id: string }
            Returns: {
              amount: number
              day: string
              expense_rows: number
              tax_amount: number
              total_amount: number
            }[]
          }
        | {
            Args: { p_branch_id?: string; p_limit?: number; p_org_id: string }
            Returns: {
              amount: number
              day: string
              expense_rows: number
              tax_amount: number
              total_amount: number
            }[]
          }
      get_forecast_entitlements: {
        Args: { p_org_id: string }
        Returns: {
          can_use_paid: boolean
          forecast_enabled: boolean
          max_forecast_history_days: number
          max_forecast_horizon_days: number
          max_forecast_runs_per_day: number
          tier_code: string
        }[]
      }
      get_forecast_entitlements_v2: {
        Args: { p_org_id: string }
        Returns: {
          can_use_paid: boolean
          forecast_enabled: boolean
          max_forecast_history_days: number
          max_forecast_horizon_days: number
          max_forecast_runs_per_day: number
          paid_forecast_enabled: boolean
          tier_code: string
        }[]
      }
      get_forecast_outputs: {
        Args: { p_run_id: string }
        Returns: {
          day: string
          p50_net_sales: number
          p80_high: number
          p80_low: number
          p95_high: number
          p95_low: number
        }[]
      }
      get_import_contract: {
        Args: { p_entity: Database["public"]["Enums"]["import_entity"] }
        Returns: {
          canonical_key: string
          data_type: string
          display_name: string
          is_required: boolean
          ordinal: number
        }[]
      }
      get_import_job: {
        Args: { p_job_id: string }
        Returns: {
          content_type: string | null
          created_at: string
          created_by: string
          entity_type: Database["public"]["Enums"]["import_entity"]
          file_size: number | null
          id: string
          metadata: Json
          org_id: string
          original_filename: string
          status: Database["public"]["Enums"]["import_job_status"]
          storage_bucket: string
          storage_path: string
          summary: Json
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "import_jobs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      get_org_entitlements: {
        Args: { p_org_id: string }
        Returns: {
          global_benchmark_enabled: boolean
          max_benchmark_plots: number
          max_branches: number
          tier_code: string
        }[]
      }
      get_org_features: {
        Args: { p_org_id: string }
        Returns: {
          forecast_enabled: boolean
          global_benchmark_enabled: boolean
          max_benchmark_plots: number
          max_branches: number
          tier_code: string
        }[]
      }
      get_platform_support_email: { Args: never; Returns: string }
      get_sales_daily:
        | {
            Args: { p_limit?: number; p_org_id: string }
            Returns: {
              day: string
              invoices: number
              net_sales: number
              tax_amount: number
              total_amount: number
            }[]
          }
        | {
            Args: { p_branch_id?: string; p_limit?: number; p_org_id: string }
            Returns: {
              day: string
              invoices: number
              net_sales: number
              tax_amount: number
              total_amount: number
            }[]
          }
      get_sales_daily_range: {
        Args: { p_end: string; p_org_id: string; p_start: string }
        Returns: {
          day: string
          net_sales: number
        }[]
      }
      get_sales_daily_range_branch: {
        Args: {
          p_branch_id: string
          p_end: string
          p_org_id: string
          p_start: string
        }
        Returns: {
          day: string
          net_sales: number
        }[]
      }
      get_top_categories_30d: {
        Args: { p_cogs_mode?: string; p_limit?: number; p_org_id: string }
        Returns: {
          category: string
          cogs: number
          gross_margin: number
          gross_profit: number
          net_sales: number
        }[]
      }
      get_top_products_30d: {
        Args: { p_cogs_mode?: string; p_limit?: number; p_org_id: string }
        Returns: {
          category: string
          cogs: number
          gross_margin: number
          gross_profit: number
          net_sales: number
          product_name: string
          sku: string
        }[]
      }
      get_unit_economics_by_sku:
        | {
            Args: { p_days?: number; p_org_id: string }
            Returns: {
              cogs_labor: number
              cogs_material: number
              cogs_overhead: number
              cogs_packaging: number
              cogs_per_unit: number
              cogs_total: number
              gross_margin: number
              gross_profit: number
              net_sales: number
              product_name: string
              sku: string
              units_sold: number
            }[]
          }
        | {
            Args: { p_branch_id?: string; p_days?: number; p_org_id: string }
            Returns: {
              cogs_per_unit: number
              cogs_total: number
              gross_margin: number
              gross_profit: number
              net_sales: number
              product_name: string
              sku: string
              units_sold: number
            }[]
          }
      get_unit_economics_by_sku_branch: {
        Args: { p_branch_id?: string; p_days?: number; p_org_id: string }
        Returns: {
          avg_price: number
          cogs_labor: number
          cogs_material: number
          cogs_overhead: number
          cogs_packaging: number
          cogs_per_unit: number
          cogs_total: number
          gross_margin: number
          gross_profit: number
          net_sales: number
          product_name: string
          sku: string
          units_sold: number
        }[]
      }
      import_expenses_from_staging: {
        Args: { p_job_id: string }
        Returns: Json
      }
      import_labor_from_staging: { Args: { p_job_id: string }; Returns: Json }
      import_products_from_staging: {
        Args: { p_job_id: string }
        Returns: Json
      }
      import_sales_from_staging: { Args: { p_job_id: string }; Returns: Json }
      is_org_member: { Args: { p_org_id: string }; Returns: boolean }
      is_org_super_admin: { Args: { p_org_id: string }; Returns: boolean }
      is_platform_admin: { Args: never; Returns: boolean }
      list_branches_for_org: {
        Args: { p_org_id: string }
        Returns: {
          branch_id: string
          code: string
          is_default: boolean
          name: string
        }[]
      }
      list_cost_center_codes: {
        Args: { p_org_id: string }
        Returns: {
          cost_center_code: string
        }[]
      }
      list_expenses_for_allocation:
        | {
            Args: { p_branch_id?: string; p_limit?: number; p_org_id: string }
            Returns: {
              allocated_amount: number
              allocation_status: string
              amount: number
              category: string
              expense_date: string
              expense_id: string
              unallocated_amount: number
              vendor: string
            }[]
          }
        | {
            Args: { p_limit?: number; p_org_id: string }
            Returns: {
              allocated_amount: number
              allocation_status: string
              amount: number
              category: string
              expense_date: string
              id: string
              reference_number: string
              vendor: string
            }[]
          }
      list_forecast_runs:
        | {
            Args: { p_limit?: number; p_org_id: string }
            Returns: {
              anchor_date: string
              created_at: string
              history_days: number
              horizon_days: number
              id: string
              message: string
              model: string
              status: string
            }[]
          }
        | {
            Args: { p_branch_id?: string; p_limit?: number; p_org_id: string }
            Returns: {
              anchor_date: string
              created_at: string
              history_days: number
              horizon_days: number
              id: string
              message: string
              model: string
              status: string
            }[]
          }
      list_import_job_rows: {
        Args: { p_job_id: string; p_limit?: number }
        Returns: {
          created_at: string
          errors: Json
          id: number
          is_valid: boolean
          job_id: string
          parsed: Json
          raw: Json
          row_number: number
        }[]
        SetofOptions: {
          from: "*"
          to: "import_job_rows"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_import_jobs: {
        Args: { p_limit?: number; p_org_id: string }
        Returns: {
          content_type: string | null
          created_at: string
          created_by: string
          entity_type: Database["public"]["Enums"]["import_entity"]
          file_size: number | null
          id: string
          metadata: Json
          org_id: string
          original_filename: string
          status: Database["public"]["Enums"]["import_job_status"]
          storage_bucket: string
          storage_path: string
          summary: Json
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "import_jobs"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_listed_orgs: {
        Args: { p_limit?: number }
        Returns: {
          name: string
          org_id: string
          support_email: string
        }[]
      }
      list_my_orgs: {
        Args: never
        Returns: {
          created_at: string
          id: string
          name: string
        }[]
      }
      list_orgs_for_dropdown: {
        Args: never
        Returns: {
          name: string
          org_id: string
          subscription_tier_code: string
          support_email: string
        }[]
      }
      norm_dim: { Args: { p: string }; Returns: string }
      org_anchor_date: { Args: { p_org_id: string }; Returns: string }
      overhead_daily: {
        Args: { p_day: string; p_org_id: string }
        Returns: number
      }
      platform_add_admin: {
        Args: { p_email: string; p_user_id: string }
        Returns: Json
      }
      platform_add_member: {
        Args: {
          p_is_admin?: boolean
          p_org_id: string
          p_status?: string
          p_user_email?: string
          p_user_id?: string
        }
        Returns: Json
      }
      platform_audit_insert: {
        Args: {
          p_action: string
          p_entity: string
          p_entity_id: string
          p_meta?: Json
          p_org_id?: string
        }
        Returns: undefined
      }
      platform_close_stale_sessions: { Args: never; Returns: number }
      platform_create_org: {
        Args: {
          p_is_listed?: boolean
          p_name: string
          p_owner_email?: string
          p_owner_user_id?: string
          p_tier_code?: string
        }
        Returns: Json
      }
      platform_find_user_id: { Args: { p_email: string }; Returns: string }
      platform_get_role_mappings: {
        Args: never
        Returns: {
          kind: string
          role_label: string
        }[]
      }
      platform_get_user_daily: {
        Args: { p_days?: number; p_user_id: string }
        Returns: {
          active_seconds: number
          day: string
          page_views: number
          sessions: number
        }[]
      }
      platform_get_user_pageviews: {
        Args: { p_days?: number; p_user_id: string }
        Returns: {
          day: string
          path: string
          views: number
        }[]
      }
      platform_list_audit: {
        Args: { p_days?: number; p_limit?: number }
        Returns: {
          action: string
          actor_email: string
          entity: string
          entity_id: string
          meta: Json
          occurred_at: string
          org_id: string
        }[]
      }
      platform_list_org_members: {
        Args: { p_org_id: string }
        Returns: {
          approved_at: string
          email: string
          requested_at: string
          role: string
          status: string
          user_id: string
        }[]
      }
      platform_list_org_role_labels: {
        Args: never
        Returns: {
          role_label: string
        }[]
      }
      platform_list_orgs: {
        Args: { p_limit?: number }
        Returns: {
          branch_count: number
          created_at: string
          is_listed: boolean
          name: string
          org_id: string
          subscription_tier_code: string
          support_email: string
        }[]
      }
      platform_list_pending_members: {
        Args: { p_limit?: number }
        Returns: {
          org_id: string
          org_name: string
          requested_at: string
          role: string
          user_email: string
          user_id: string
        }[]
      }
      platform_list_user_sessions: {
        Args: { p_limit?: number; p_user_id: string }
        Returns: {
          end_reason: string
          ended_at: string
          last_seen_at: string
          org_id: string
          org_name: string
          started_at: string
          user_agent: string
        }[]
      }
      platform_list_users: {
        Args: { p_limit?: number }
        Returns: {
          created_at: string
          email: string
          is_online: boolean
          last_seen_at: string
          orgs: Json
          user_id: string
        }[]
      }
      platform_purge_activity: {
        Args: {
          p_keep_audit_days?: number
          p_keep_daily_days?: number
          p_keep_sessions_days?: number
        }
        Returns: Json
      }
      platform_remove_member: {
        Args: { p_org_id: string; p_user_id: string }
        Returns: Json
      }
      platform_set_member_admin: {
        Args: { p_is_admin: boolean; p_org_id: string; p_user_id: string }
        Returns: Json
      }
      platform_set_member_role_kind: {
        Args: { p_kind: string; p_org_id: string; p_user_id: string }
        Returns: Json
      }
      platform_set_member_status: {
        Args: {
          p_org_id: string
          p_role?: string
          p_status: string
          p_user_id: string
        }
        Returns: Json
      }
      platform_set_org_tier: {
        Args: { p_org_id: string; p_tier_code: string }
        Returns: Json
      }
      platform_set_role_mapping: {
        Args: { p_kind: string; p_role_label: string }
        Returns: Json
      }
      platform_update_org: {
        Args: { p_is_listed: boolean; p_org_id: string; p_tier_code: string }
        Returns: Json
      }
      preview_expense_allocation: {
        Args: { p_expense_id: string }
        Returns: Json
      }
      request_org_access: { Args: { p_org_id: string }; Returns: Json }
      safe_org_role: {
        Args: { p: string }
        Returns: Database["public"]["Enums"]["org_role"]
      }
      save_import_job_mapping: {
        Args: { p_job_id: string; p_mapping: Json }
        Returns: {
          content_type: string | null
          created_at: string
          created_by: string
          entity_type: Database["public"]["Enums"]["import_entity"]
          file_size: number | null
          id: string
          metadata: Json
          org_id: string
          original_filename: string
          status: Database["public"]["Enums"]["import_job_status"]
          storage_bucket: string
          storage_path: string
          summary: Json
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "import_jobs"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      seed_cost_engine_demo: { Args: { p_org_id: string }; Returns: Json }
      select_loaded_hourly_rate: {
        Args: { p_as_of: string; p_org_id: string; p_role_code: string }
        Returns: number
      }
      select_recipe_version_id: {
        Args: { p_as_of: string; p_org_id: string; p_sku: string }
        Returns: string
      }
      start_import_job: { Args: { p_job_id: string }; Returns: Json }
      suggest_expense_allocations: {
        Args: { p_expense_id: string }
        Returns: Json
      }
      to_base_qty: {
        Args: { p_base_uom: string; p_qty: number; p_uom: string }
        Returns: number
      }
      track_user_page_view: {
        Args: { p_org_id: string; p_path: string }
        Returns: Json
      }
      track_user_session_end: {
        Args: { p_reason?: string; p_session_id: string }
        Returns: Json
      }
      track_user_session_heartbeat: {
        Args: {
          p_delta_seconds?: number
          p_org_id: string
          p_session_id: string
        }
        Returns: Json
      }
      track_user_session_start: {
        Args: { p_org_id: string; p_user_agent?: string }
        Returns: string
      }
      wac_unit_cost: {
        Args: {
          p_as_of: string
          p_ingredient_id: string
          p_org_id: string
          p_window_days?: number
        }
        Returns: number
      }
    }
    Enums: {
      import_entity: "sales" | "expenses" | "products" | "labor" | "unknown"
      import_job_status:
        | "uploaded"
        | "parsed"
        | "validated"
        | "imported"
        | "failed"
      org_role: "super_admin" | "admin" | "analyst" | "viewer"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  analytics: {
    Enums: {},
  },
  public: {
    Enums: {
      import_entity: ["sales", "expenses", "products", "labor", "unknown"],
      import_job_status: [
        "uploaded",
        "parsed",
        "validated",
        "imported",
        "failed",
      ],
      org_role: ["super_admin", "admin", "analyst", "viewer"],
    },
  },
} as const
