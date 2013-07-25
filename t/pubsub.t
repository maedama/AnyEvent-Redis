use strict;
use Test::More;
use t::Redis;

test_redis {
    my $sub = shift;
    my $port = shift;

    my $info = $sub->info->recv;
    if($info->{redis_version} lt "1.3.10") {
      plan skip_all => "No PUBLISH/SUBSCRIBE support in this Redis version";
    }

    my $pub = AnyEvent::Redis->new(host => "127.0.0.1", port => $port);

    # $pub is for publishing
    # $sub is for subscribing

    my $x = 0;
    my $expected_x = 0;

    my $count = 0;
    my $expected_count = 10;

    $sub->all_cv->begin;
    $sub->subscribe("test.1", sub {
            my($message, $chan) = @_;
            $x += $message;
            if(++$count == $expected_count) {
                $sub->unsubscribe("test.1");
                is $x, $expected_x, "Messages received, values as expected";
            }
        });
    
    subtest 'subscribe immediately called after unsub' => sub {
        my $first_sub_call_count = 0;
        my $second_sub_call_count = 0;
        my $cv = AE::cv;
        $sub->subscribe("test.2", sub {
            $first_sub_call_count++;
            $cv->send;
        });
        $sub->unsubscribe("test.2");
        $sub->subscribe("test.2", sub {
            $second_sub_call_count;
            $cv->send;
        });
        my $timer = AnyEvent->timer(
            cb => sub { $cv->croak; },
            after => 2,
        );
        $pub->publish("test.2", "foo");
        $cv->recv;
        is $first_sub_call_count, 0;
        is $second_sub_call_count, 0;
        undef $timer;
    };

    # Pattern subscription
    my $y = 0;
    my $expected_y = 0;

    my $count2 = 0;

    $sub->psubscribe("testp.*", sub {
            my($message, $chan) = @_;
            $y += $message;
            if(++$count2 == $expected_count) {
                $sub->punsubscribe("testp.*");
                is $y, $expected_y, "Messages received, values as expected";
            }
        });

    for(1 .. $expected_count) {
        my $cv = $pub->publish("test.1" => $_);
        $expected_x += $_;
        # Need to be sure a client has subscribed
        $expected_x = 0, redo unless $cv->recv;
    }

    for(1 .. $expected_count) {
        my $cv = $pub->publish("testp.$_" => $_);
        $expected_y += $_;
        # Need to be sure a client has subscribed
        $expected_y = 0, redo unless $cv->recv;
    }

    $sub->all_cv->end;
    done_testing;
};

