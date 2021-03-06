require 'active_record'
require 'gh'

class User < ActiveRecord::Base
  autoload :Oauth, 'travis/model/user/oauth'

  has_many :tokens
  has_many :memberships
  has_many :organizations, :through => :memberships
  has_many :permissions
  has_many :repositories, :through => :permissions
  has_many :emails

  attr_accessible :name, :login, :email, :github_id, :github_oauth_token, :gravatar_id, :locale

  before_create :set_as_recent
  after_create :create_a_token
  after_commit :sync, on: :create

  serialize :github_scopes
  before_save :track_github_scopes

  serialize :github_oauth_token, Travis::Model::EncryptedColumn.new

  class << self
    def with_permissions(permissions)
      where(:permissions => permissions).includes(:permissions)
    end

    def authenticate_by(options)
      options = options.symbolize_keys

      if user = User.find_by_login(options[:login])
        user if user.tokens.any? { |t| t.token == options[:token] }
      end
    end

    def find_or_create_for_oauth(payload)
      Oauth.find_or_create_by(payload)
    end

    def with_github_token
      where('github_oauth_token IS NOT NULL')
    end
  end

  def to_json
    keys = %w/id login email name locale github_id gravatar_id is_syncing synced_at updated_at created_at/
    { 'user' => attributes.slice(*keys) }.to_json
  end

  def permission?(roles, options = {})
    roles, options = nil, roles if roles.is_a?(Hash)
    scope = permissions.where(options)
    scope = scope.by_roles(roles) if roles
    scope.any?
  end

  def first_sync?
    synced_at.nil?
  end

  def sync
    Travis.run_service(:sync_user, self) # TODO remove once apps use the service
  end

  def syncing?
    is_syncing?
  end

  def service_hook(options = {})
    service_hooks(options).first
  end

  def service_hooks(options = {})
    hooks = repositories.administratable.order('owner_name, name')
    # TODO remove owner_name/name once we're on api everywhere
    if options.key?(:id)
      hooks = hooks.where(options.slice(:id))
    elsif options.key?(:owner_name) || options.key?(:name)
      hooks = hooks.where(options.slice(:id, :owner_name, :name))
    end
    hooks
  end

  def organization_ids
    @organization_ids ||= memberships.map(&:organization_id)
  end

  def repository_ids
    @repository_ids ||= permissions.map(&:repository_id)
  end

  def recently_signed_up?
    @recently_signed_up || false
  end

  def profile_image_hash
    # TODO:
    #   If Github always sends valid gravatar_id in oauth payload (need to check that)
    #   then these fallbacks (email hash and zeros) are superfluous and can be removed.
    gravatar_id.presence || (email? && Digest::MD5.hexdigest(email)) || '0' * 32
  end

  def github_scopes
    return [] unless github_oauth_token
    read_attribute(:github_scopes) || []
  end

  def correct_scopes?
    missing = Oauth.wanted_scopes - github_scopes
    missing.empty?
  end

  protected

    def track_github_scopes
      self.github_scopes = Travis::Github.scopes_for(self) if github_oauth_token_changed? or github_scopes.blank?
    end

    def set_as_recent
      @recently_signed_up = true
    end

    def create_a_token
      self.tokens.create!
    end
end
