module AASM
  class Event

    attr_reader :name, :options

    def initialize(name, options = {}, &block)
      @name = name
      @transitions = []
      update(options, &block)
    end

    # a neutered version of fire - it doesn't actually fire the event, it just
    # executes the transition guards to determine if a transition is even
    # an option given current conditions.
    def may_fire?(obj, to_state=nil, *args)
      _fire(obj, true, to_state, *args) # true indicates test firing
    end

    def fire(obj, to_state=nil, *args)
      _fire(obj, false, to_state, *args) # false indicates this is not a test (fire!)
    end

    def transitions_from_state?(state)
      transitions_from_state(state).any?
    end

    def transitions_from_state(state)
      @transitions.select { |t| t.from == state }
    end

    def transitions_to_state?(state)
      transitions_to_state(state).any?
    end

    def transitions_to_state(state)
      @transitions.select { |t| t.to == state }
    end

    def all_transitions
      @transitions
    end

    def fire_callbacks(callback_name, record, *args)
      invoke_callbacks(@options[callback_name], record, args)
    end

    def ==(event)
      if event.is_a? Symbol
        name == event
      else
        name == event.name
      end
    end

  private

    def update(options = {}, &block)
      @options = options
      if block then
        instance_eval(&block)
      end
      self
    end

    # Execute if test? == false, otherwise return true/false depending on whether it would fire
    def _fire(obj, test, to_state=nil, *args)
      if @transitions.map(&:from).any?
        transitions = @transitions.select { |t| t.from == obj.aasm_current_state }
        return nil if transitions.size == 0
      else
        transitions = @transitions
      end

      result = test ? false : nil
      transitions.each do |transition|
        next if to_state and !Array(transition.to).include?(to_state)
        if transition.perform(obj, *args)
          if test
            result = true
          else
            result = to_state || Array(transition.to).first
            transition.execute(obj, *args)
          end

          break
        end
      end
      result
    end

    def invoke_callbacks(code, record, args)
      case code
        when Symbol, String
          record.send(code, *args)
          true
        when Proc
          record.instance_exec(*args, &code)
          true
        when Array
          code.each {|a| invoke_callbacks(a, record, args)}
          true
        else
          false
      end
    end

    ## DSL interface
    def transitions(trans_opts)
      # Create a separate transition for each from state to the given state
      Array(trans_opts[:from]).each do |s|
        @transitions << AASM::Transition.new(trans_opts.merge({:from => s.to_sym}))
      end
      # Create a transition if to is specified without from (transitions from ANY state)
      @transitions << AASM::Transition.new(trans_opts) if @transitions.empty? && trans_opts[:to]
    end

    [:after, :before, :error, :success].each do |callback_name|
      define_method callback_name do |*args, &block|
        options[callback_name] = Array(options[callback_name])
        options[callback_name] << block if block
        options[callback_name] += Array(args)
      end
    end
  end
end # AASM