module Travis
  module Services
    class CancelJob < Base
      extend Travis::Instrumentation

      register :cancel_job

      def run
        cancel if can_cancel?
      end
      instrument :run

      def messages
        messages = []
        messages << { :notice => 'The job was successfully cancelled.' } if can_cancel?
        messages << { :error  => 'You are not authorized to cancel this job.' } unless authorized?
        messages << { :error  => "The job could not be cancelled because it is currently #{job.state}." } unless job.cancelable?
        messages
      end

      def cancel
        job.cancel!
      end

      def can_cancel?
        authorized? && job.cancelable?
      end

      def authorized?
        current_user.permission?(:push, :repository_id => job.repository_id)
      end

      def job
        @job ||= run_service(:find_job, params)
      end

      class Instrument < Notification::Instrument
        def run_completed
          publish(
            :msg => "for <Job id=#{target.job.id}> (#{target.current_user.login})",
            :result => result
          )
        end
      end
      Instrument.attach_to(self)
    end
  end
end
