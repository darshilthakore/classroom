# frozen_string_literal: true

class Organization < ApplicationRecord
  include Flippable
  include Sluggable

  update_index("organization#organization") { self }

  default_scope { where(deleted_at: nil) }

  has_many :assignments,              dependent: :destroy
  has_many :groupings,                dependent: :destroy
  has_many :group_assignments,        dependent: :destroy
  has_many :repo_accesses,            dependent: :destroy

  belongs_to :roster, optional: true

  has_and_belongs_to_many :users

  validates :github_id, presence: true, uniqueness: true

  validates :title, presence: true
  validates :title, length: { maximum: 60 }

  validates :slug, uniqueness: true

  validates :webhook_id, uniqueness: true, allow_nil: true

  before_destroy :silently_remove_organization_webhook

  def all_assignments(with_invitations: false)
    return assignments + group_assignments unless with_invitations

    assignments.includes(:assignment_invitation) + \
      group_assignments.includes(:group_assignment_invitation)
  end

  def github_client(random_token = !Rails.env.test?)
    if random_token
      org_tokens = users.order("RANDOM()").pluck(:token)
      
      org_tokens.each do |token|
        client = Octokit::Client.new(access_token: token)
        org = GitHubOrganization.new(client. github_id)
        return client if org.admin?
      end
    else
      # Return first token
      token = users.first.token unless users.first.nil?
      return Octokit::Client.new(access_token: token)
    end
    nil
  end

  def github_organization
    @github_organization ||= GitHubOrganization.new(github_client, github_id)
  end

  def slugify
    self.slug = "#{github_id} #{title}".parameterize
  end

  def one_owner_remains?
    users.count == 1
  end

  def silently_remove_organization_webhook
    begin
      github_organization.remove_organization_webhook(webhook_id)
    rescue GitHub::Error => err
      logger.info err.message
    end

    true
  end
end
