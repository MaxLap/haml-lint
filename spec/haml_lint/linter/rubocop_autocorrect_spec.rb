# frozen_string_literal: true

describe HamlLint::Linter::RuboCop do
  context 'autocorrect testing' do
    # The goal is not to test rubocop the gem, so no need to test the details using both
    # :safe and :all
    include_context 'linter', autocorrect: :all

    context 'for silent script' do
      context 'fixes a single-line one' do
        let(:haml) { <<~HAML }
          - foo(bar , 42)
        HAML

        it do
          document.source.should == <<~HAML
            - foo(bar, 42)
          HAML
          document.source_was_changed.should be true
        end

        context 'that was indented by a tag' do
          let(:haml) { <<~HAML }
            %tag
              - foo(bar , 42)
          HAML

          it do
            document.source.should == <<~HAML
              %tag
                - foo(bar, 42)
            HAML
            document.source_was_changed.should be true
          end
        end

        context 'that was indented by ruby code' do
          let(:haml) { <<~HAML }
            - deeper do
              - foo(bar , 42)
          HAML

          it do
            document.source.should == <<~HAML
              - deeper do
                - foo(bar, 42)
            HAML
            document.source_was_changed.should be true
          end
        end
      end

      context 'leave a correct single-line as-is' do
        let(:haml) { <<~HAML }
          - foo(bar, 42)
        HAML

        it do
          document.source.should == <<~HAML
            - foo(bar, 42)
          HAML
          document.source_was_changed.should be false
        end
      end

      context 'multiple silent-scripts' do
        let(:haml) { <<~HAML }
          - foo(bar , 42)
          - zee(:a => 5)
        HAML

        it do
          document.source.should == <<~HAML
            - foo(bar, 42)
            - zee(a: 5)
          HAML
          document.source_was_changed.should be true
        end

        context 'with a blank line between' do
          let(:haml) { <<~HAML }
            - foo(bar , 42)

            - zee(:a => 5)
          HAML

          it do
            document.source.should == <<~HAML
              - foo(bar, 42)

              - zee(a: 5)
            HAML
            document.source_was_changed.should be true
          end
        end
      end

      context 'fixes a multi-line one' do
        let(:haml) { <<~HAML }
          - foo(abc ,   something,
                little_thing ,  :abc =>  42)
        HAML

        it do
          document.source.should == <<~HAML
            - foo(abc, something,
                  little_thing, abc: 42)
          HAML
          document.source_was_changed.should be true
        end

        context 'with spaces after the line splitting comma' do
          # rubocop:disable Lint/LiteralInInterpolation
          let(:haml) { <<~HAML }
            - foo(abc ,   something,#{'  '}
                  little_thing ,  :abc =>  42)
          HAML
          # rubocop:enable Lint/LiteralInInterpolation

          it do
            document.source.should == <<~HAML
              - foo(abc, something,
                    little_thing, abc: 42)
            HAML
            document.source_was_changed.should be true
          end
        end

        context 'and extra indent' do
          let(:haml) { <<~HAML }
            - deeper do
              - foo(abc ,   something,
                        little_thing ,  :abc =>  42)
          HAML

          it do
            document.source.should == <<~HAML
              - deeper do
                - foo(abc, something,
                      little_thing, abc: 42)
            HAML
            document.source_was_changed.should be true
          end
        end

        context 'and missing indent' do
          let(:haml) { <<~HAML }
            - deeper do
              - foo(abc ,   something,
                 little_thing ,  :abc =>  42)
          HAML

          it do
            document.source.should == <<~HAML
              - deeper do
                - foo(abc, something,
                      little_thing, abc: 42)
            HAML
            document.source_was_changed.should be true
          end
        end

        context 'and less indented than the tag is' do
          let(:haml) { <<~HAML }
            - deeper do
              - foo(abc ,   something,
             little_thing ,  :abc =>  42)
          HAML

          it do
            document.source.should == <<~HAML
              - deeper do
                - foo(abc, something,
                      little_thing, abc: 42)
            HAML
            document.source_was_changed.should be true
          end
        end
      end
    end

    context 'for non-silent script' do
      context 'fixes a single-line one' do
        let(:haml) { <<~HAML }
          = foo(bar , 42)
        HAML

        it do
          document.source.should == <<~HAML
            = foo(bar, 42)
          HAML
          document.source_was_changed.should be true
        end

        context 'that was indented by haml tag' do
          let(:haml) { <<~HAML }
            %tag
              = foo(bar , 42)
          HAML

          it do
            document.source.should == <<~HAML
              %tag
                = foo(bar, 42)
            HAML
            document.source_was_changed.should be true
          end
        end

        context 'that was indented by ruby code' do
          let(:haml) { <<~HAML }
            - deeper do
              = foo(bar , 42)
          HAML

          it do
            document.source.should == <<~HAML
              - deeper do
                = foo(bar, 42)
            HAML
            document.source_was_changed.should be true
          end
        end
      end

      context 'leave a correct single-line as-is' do
        let(:haml) { <<~HAML }
          = foo(bar, 42)
        HAML

        it do
          document.source.should == <<~HAML
            = foo(bar, 42)
          HAML
          document.source_was_changed.should be false
        end
      end

      context 'fixes a multi-line one' do
        let(:haml) { <<~HAML }
          = foo(abc ,   something,
                little_thing ,  :abc =>  42)
        HAML

        it do
          document.source.should == <<~HAML
            = foo(abc, something,
                  little_thing, abc: 42)
          HAML
          document.source_was_changed.should be true
        end

        context 'with spaces after the line splitting comma' do
          # rubocop:disable Lint/LiteralInInterpolation
          let(:haml) { <<~HAML }
            = foo(abc ,   something,#{'  '}
                  little_thing ,  :abc =>  42)
          HAML
          # rubocop:enable Lint/LiteralInInterpolation

          it do
            document.source.should == <<~HAML
              = foo(abc, something,
                    little_thing, abc: 42)
            HAML
            document.source_was_changed.should be true
          end
        end

        context 'and extra indent' do
          let(:haml) { <<~HAML }
            - deeper do
              = foo(abc ,   something,
                        little_thing ,  :abc =>  42)
          HAML

          it do
            document.source.should == <<~HAML
              - deeper do
                = foo(abc, something,
                      little_thing, abc: 42)
            HAML
            document.source_was_changed.should be true
          end
        end

        context 'and missing indent' do
          let(:haml) { <<~HAML }
            - deeper do
              = foo(abc ,   something,
                 little_thing ,  :abc =>  42)
          HAML

          it do
            document.source.should == <<~HAML
              - deeper do
                = foo(abc, something,
                      little_thing, abc: 42)
            HAML
            document.source_was_changed.should be true
          end
        end

        context 'and less indented than the tag is' do
          let(:haml) { <<~HAML }
            - deeper do
              = foo(abc ,   something,
             little_thing ,  :abc =>  42)
          HAML

          it do
            document.source.should == <<~HAML
              - deeper do
                = foo(abc, something,
                      little_thing, abc: 42)
            HAML
            document.source_was_changed.should be true
          end
        end
      end

      context 'multiple silent-scripts' do
        let(:haml) { <<~HAML }
          = foo(bar , 42)
          = zee(:a => 5)
        HAML

        it do
          document.source.should == <<~HAML
            = foo(bar, 42)
            = zee(a: 5)
          HAML
          document.source_was_changed.should be true
        end

        context 'with a blank line between' do
          let(:haml) { <<~HAML }
            = foo(bar , 42)

            = zee(:a => 5)
          HAML

          it do
            document.source.should == <<~HAML
              = foo(bar, 42)

              = zee(a: 5)
            HAML
            document.source_was_changed.should be true
          end
        end
      end
    end

    context 'for ruby filter' do
      context 'fixes a single-line one' do
        let(:haml) { <<~HAML }
          :ruby
            foo(bar , 42)
        HAML

        it do
          document.source.should == <<~HAML
            :ruby
              foo(bar, 42)
          HAML
          document.source_was_changed.should be true
        end
      end

      context 'leave a correct single-line as-is' do
        let(:haml) { <<~HAML }
          :ruby
            foo(bar, 42)
        HAML

        it do
          document.source.should == <<~HAML
            :ruby
              foo(bar, 42)
          HAML
          document.source_was_changed.should be false
        end
      end

      context 'fixes a multi-line one' do
        let(:haml) { <<~HAML }
          :ruby
            foo(bar , 42)
            zee(:a => 5)
        HAML

        it do
          document.source.should == <<~HAML
            :ruby
              foo(bar, 42)
              zee(a: 5)
          HAML
          document.source_was_changed.should be true
        end

        context 'with a blank line between' do
          let(:haml) { <<~HAML }
            :ruby
              foo(bar , 42)

              zee(:a => 5)
          HAML

          it do
            document.source.should == <<~HAML
              :ruby
                foo(bar, 42)

                zee(a: 5)
            HAML
            document.source_was_changed.should be true
          end
        end

        context 'with indentation inside' do
          let(:haml) { <<~HAML }
            :ruby
              if abc
                foo(bar , 42)
                zee(:a => 5)
              end
          HAML

          it do
            document.source.should == <<~HAML
              :ruby
                if abc
                  foo(bar, 42)
                  zee(a: 5)
                end
            HAML
            document.source_was_changed.should be true
          end
        end
      end

      context 'removes extra indentation inside' do
        let(:haml) { <<~HAML }
          :ruby
            if abc
                foo(bar, 42)
                zee(a: 5)
            end
        HAML

        it do
          document.source.should == <<~HAML
            :ruby
              if abc
                foo(bar, 42)
                zee(a: 5)
              end
          HAML
          document.source_was_changed.should be true
        end
      end

      context 'adds missing indentation inside' do
        let(:haml) { <<~HAML }
          :ruby
            if abc
            foo(bar, 42)
            zee(a: 5)
            end
        HAML

        it do
          document.source.should == <<~HAML
            :ruby
              if abc
                foo(bar, 42)
                zee(a: 5)
              end
          HAML
          document.source_was_changed.should be true
        end
      end

      context 'fixes by adding empty lines' do
        let(:haml) { <<~HAML }
          :ruby
            def a; end
            def b; end
        HAML

        it do
          document.source.should == <<~HAML
            :ruby
              def a; end

              def b; end
          HAML
          document.source_was_changed.should be true
        end

        context 'while moving empty lines' do
          let(:haml) { <<~HAML }
            :ruby
              def a; end
              def b; end

              # The empty-line above can mess with the merging logic
          HAML

          it do
            document.source.should == <<~HAML
              :ruby
                def a; end

                def b; end

                # The empty-line above can mess with the merging logic
            HAML
            document.source_was_changed.should be true
          end
        end
      end

      context 'that was indented by a tag' do
        let(:haml) { <<~HAML }
          %tag
            :ruby
              foo(bar , 42)
        HAML

        it do
          document.source.should == <<~HAML
            %tag
              :ruby
                foo(bar, 42)
          HAML
          document.source_was_changed.should be true
        end
      end

      context 'that was indented by ruby code' do
        let(:haml) { <<~HAML }
          - deeper do
            :ruby
              foo(bar , 42)
        HAML

        it do
          document.source.should == <<~HAML
            - deeper do
              :ruby
                foo(bar, 42)
          HAML
          document.source_was_changed.should be true
        end
      end
    end

    context 'for tag' do
      context 'fixes attribute hash' do
        let(:haml) { <<~HAML }
          %tag{abc:   42}
        HAML

        it do
          document.source.should == <<~HAML
            %tag{abc: 42}
          HAML
          document.source_was_changed.should be true
        end

        context 'with multiple lines' do
          let(:haml) { <<~HAML }
            %tag{abc:   42,
                 :bar => :cool}
          HAML

          it do
            document.source.should == <<~HAML
              %tag{abc: 42,
                   bar: :cool}
            HAML
            document.source_was_changed.should be true
          end

          context 'and extra indent' do
            let(:haml) { <<~HAML }
              %tag{abc:   42,
                           :bar => :cool}
            HAML

            it do
              document.source.should == <<~HAML
                %tag{abc: 42,
                     bar: :cool}
              HAML
              document.source_was_changed.should be true
            end
          end

          context 'and missing indent' do
            let(:haml) { <<~HAML }
              %tag-is-long{abc:   42,
                :bar => :cool}
            HAML

            it do
              document.source.should == <<~HAML
                %tag-is-long{abc: 42,
                             bar: :cool}
              HAML
              document.source_was_changed.should be true
            end
          end

          context 'and less indented than the tag is' do
            let(:haml) { <<~HAML }
              %tag
                %tag.long-class-too{abc:   42,
              :bar => :cool}
            HAML

            it do
              document.source.should == <<~HAML
                %tag
                  %tag.long-class-too{abc: 42,
                                      bar: :cool}
              HAML
              document.source_was_changed.should be true
            end
          end
        end

        context 'that was indented by a tag' do
          let(:haml) { <<~HAML }
            %tag
              %tag{abc:   42, :bar => :cool}
          HAML

          it do
            document.source.should == <<~HAML
              %tag
                %tag{abc: 42, bar: :cool}
            HAML
            document.source_was_changed.should be true
          end
        end

        context 'that was indented by ruby code' do
          let(:haml) { <<~HAML }
            - deeper do
              %tag{abc:   42, :bar => :cool}
          HAML

          it do
            document.source.should == <<~HAML
              - deeper do
                %tag{abc: 42, bar: :cool}
            HAML
            document.source_was_changed.should be true
          end
        end
      end

      context 'ignores old style attribute hash' do
        let(:haml) { <<~HAML }
          %tag(abc  =  42)
        HAML

        it do
          document.source.should == <<~HAML
            %tag(abc  =  42)
          HAML
          document.source_was_changed.should be false
        end
      end

      context 'fixes attribute methods' do
        let(:haml) { <<~HAML }
          %tag{foo(bar , 42)}
        HAML

        it do
          document.source.should == <<~HAML
            %tag{foo(bar, 42)}
          HAML
          document.source_was_changed.should be true
        end

        context 'that was indented by a tag' do
          let(:haml) { <<~HAML }
            %tag
              %tag{foo(bar , 42)}
          HAML

          it do
            document.source.should == <<~HAML
              %tag
                %tag{foo(bar, 42)}
            HAML
            document.source_was_changed.should be true
          end
        end

        context 'that was indented by ruby code' do
          let(:haml) { <<~HAML }
            - deeper do
              %tag{foo(bar , 42)}
          HAML

          it do
            document.source.should == <<~HAML
              - deeper do
                %tag{foo(bar, 42)}
            HAML
            document.source_was_changed.should be true
          end
        end
      end

      context 'fixes script' do
        let(:haml) { <<~HAML }
          %tag= foo(bar , 42)
        HAML

        it do
          document.source.should == <<~HAML
            %tag= foo(bar, 42)
          HAML
          document.source_was_changed.should be true
        end

        context 'that was indented by a tag' do
          let(:haml) { <<~HAML }
            %tag
              %tag= foo(bar , 42)
          HAML

          it do
            document.source.should == <<~HAML
              %tag
                %tag= foo(bar, 42)
            HAML
            document.source_was_changed.should be true
          end
        end

        context 'that was indented by ruby code' do
          let(:haml) { <<~HAML }
            - deeper do
              %tag= foo(bar , 42)
          HAML

          it do
            document.source.should == <<~HAML
              - deeper do
                %tag= foo(bar, 42)
            HAML
            document.source_was_changed.should be true
          end
        end

        context 'with multiple lines' do
          let(:haml) { <<~HAML }
            %tag= foo(abc ,   something,
                      little_thing ,  :abc =>  42)
          HAML

          it do
            document.source.should == <<~HAML
              %tag= foo(abc, something,
                        little_thing, abc: 42)
            HAML
            document.source_was_changed.should be true
          end

          context 'and extra indent' do
            let(:haml) { <<~HAML }
              %tag= foo(abc ,   something,
                             little_thing ,  :abc =>  42)
            HAML

            it do
              document.source.should == <<~HAML
                %tag= foo(abc, something,
                          little_thing, abc: 42)
              HAML
              document.source_was_changed.should be true
            end
          end

          context 'and missing indent' do
            let(:haml) { <<~HAML }
              %tag= foo(abc ,   something,
                 little_thing ,  :abc =>  42)
            HAML

            it do
              document.source.should == <<~HAML
                %tag= foo(abc, something,
                          little_thing, abc: 42)
              HAML
              document.source_was_changed.should be true
            end
          end

          context 'and less indented than the tag is' do
            let(:haml) { <<~HAML }
              %tag
                %tag= foo(abc ,   something,
              little_thing ,  :abc =>  42)
            HAML

            it do
              document.source.should == <<~HAML
                %tag
                  %tag= foo(abc, something,
                            little_thing, abc: 42)
              HAML
              document.source_was_changed.should be true
            end
          end
        end
      end
    end

    context 'fixes interpolation of plain line' do
      let(:haml) { <<~HAML }
        hello \#{foo(bar , 42)} world \#{zee(:a =>  5)}!!
      HAML

      it do
        document.source.should == <<~HAML
          hello \#{foo(bar, 42)} world \#{zee(a: 5)}!!
        HAML
        document.source_was_changed.should be true
      end

      context 'that was indented by a tag' do
        let(:haml) { <<~HAML }
          %tag
            hello \#{foo(bar , 42)} world \#{zee(:a =>  5)}!!
        HAML

        it do
          document.source.should == <<~HAML
            %tag
              hello \#{foo(bar, 42)} world \#{zee(a: 5)}!!
          HAML
          document.source_was_changed.should be true
        end
      end

      context 'that was indented by ruby code' do
        let(:haml) { <<~HAML }
          - deeper do
            hello \#{foo(bar , 42)} world \#{zee(:a =>  5)}!!
        HAML

        it do
          document.source.should == <<~HAML
            - deeper do
              hello \#{foo(bar, 42)} world \#{zee(a: 5)}!!
          HAML
          document.source_was_changed.should be true
        end
      end
    end

    context 'fixes interpolation of non-ruby filter' do
      let(:haml) { <<~HAML }
        :filter
          hello \#{foo(bar , 42)} world
      HAML

      it do
        document.source.should == <<~HAML
          :filter
            hello \#{foo(bar, 42)} world
        HAML
        document.source_was_changed.should be true
      end

      context 'with multiple lines in the filter' do
        let(:haml) { <<~HAML }
          :filter
            hello \#{foo(bar , 42)} world

            Some \#{zee(:abc =>  5)} thing
        HAML

        it do
          document.source.should == <<~HAML
            :filter
              hello \#{foo(bar, 42)} world

              Some \#{zee(abc: 5)} thing
          HAML
          document.source_was_changed.should be true
        end
      end

      context 'that was indented by a tag' do
        let(:haml) { <<~HAML }
          %tag
            :filter
              hello \#{foo(bar , 42)} world
        HAML

        it do
          document.source.should == <<~HAML
            %tag
              :filter
                hello \#{foo(bar, 42)} world
          HAML
          document.source_was_changed.should be true
        end
      end

      context 'that was indented by ruby code' do
        let(:haml) { <<~HAML }
          - deeper do
            :filter
              hello \#{foo(bar , 42)} world
        HAML

        it do
          document.source.should == <<~HAML
            - deeper do
              :filter
                hello \#{foo(bar, 42)} world
          HAML
          document.source_was_changed.should be true
        end
      end
    end

    context 'random file test' do
      let(:haml) { <<~'HAML' }
        - a  =  1
      HAML

      it do
        document.source.should == <<~HAML
          - a = 1
        HAML
        document.source_was_changed.should be true
      end
    end
  end
end
