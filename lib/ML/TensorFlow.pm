package ML::TensorFlow;
use 5.14.2;
use warnings;

require Exporter;

our $VERSION;
BEGIN { $VERSION = '0.01'; }

use XSLoader;
BEGIN { XSLoader::load('ML::TensorFlow', $VERSION); }

use Scalar::Util ();
require bytes;

use ML::TensorFlow::CAPI qw(:all);

use Exporter 'import';
our @EXPORT_OK;
BEGIN {
  push @EXPORT_OK, @ML::TensorFlow::CAPI::EXPORT_OK;
}
our %EXPORT_TAGS = (all => \@EXPORT_OK);

use constant {
  Status         => __PACKAGE__ . "::Status",
  Session        => __PACKAGE__ . "::Session",
  SessionOptions => __PACKAGE__ . "::SessionOptions",
  Tensor         => __PACKAGE__ . "::Tensor",
  Buffer         => __PACKAGE__ . "::Buffer",
  Graph          => __PACKAGE__ . "::Graph",
};
push @EXPORT_OK, qw(Status SessionOptions Session Tensor Buffer Graph);

package ML::TensorFlow::Status {
  sub new {
    my ($class) = @_;
    my $s = ML::TensorFlow::CAPI::TF_NewStatus();
    my $self = bless(\$s => $class);
    # The following is not necessary since it's the default (but not documented as such?)
    #$self->set_status(ML::TensorFlow::CAPI::TF_Code_Enum()->{TF_OK}, "");
    return $self;
  }

  sub DESTROY {
    my ($self) = @_;
    ML::TensorFlow::CAPI::TF_DeleteStatus($$self);
  }

  sub is_ok { 
    my ($self) = @_;
    my $code = $self->get_code;
    return($code == ML::TensorFlow::CAPI::TF_Code_Enum()->{TF_OK});
  }

  sub set_status {
    my ($self, $code, $message) = @_;
    ML::TensorFlow::CAPI::TF_SetStatus($$self, 0+$code, $message);
  }

  sub get_code {
    my ($self) = @_;
    return ML::TensorFlow::CAPI::TF_GetCode($$self);
  }

  sub get_message {
    my ($self) = @_;
    return ML::TensorFlow::CAPI::TF_Message($$self);
  }
}; # end Status



package ML::TensorFlow::SessionOptions {
  sub new {
    my ($class) = @_;
    my $s = ML::TensorFlow::CAPI::TF_NewSessionOptions();
    my $self = bless(\$s => $class);

    $self->set_target("");
    $self->set_config("");
    return $self;
  }

  sub DESTROY {
    my ($self) = @_;
    ML::TensorFlow::CAPI::TF_DeleteSessionOptions($$self);
  }

  sub set_target {
    my ($self, $target) = @_;
    ML::TensorFlow::CAPI::TF_SetTarget($$self, $target); # FIXME don't know FFI::Platypus well enough, but normally in XS calls, there's a risk because Perl strings aren't guaranteed to be NUL terminated!
  }

  # TODO test
  sub set_config {
    my ($self, $protoblob) = @_;
    my $status = ML::TensorFlow::Status->new();
    ML::TensorFlow::CAPI::TF_SetConfig($$self, $protoblob, bytes::length($protoblob), $$status);
    return $status;
  }

}; # end SessionOptions


# internal to ::Graph for now
package ML::TensorFlow::_ImportGraphDefOptions {
  sub new {
    my ($class, $opt) = @_;
    $opt ||= {};
    my $options = ML::TensorFlow::CAPI::TF_NewImportGraphDefOptions();
    if (defined $opt->{prefix}) {
      ML::TensorFlow::CAPI::TF_ImportGraphDefOptionsSetPrefix($options, $opt->{prefix});
    }
    return bless(\$options => $class);
  }

  sub DESTROY {
    my ($self) = @_;
    ML::TensorFlow::TF_DeleteImportGraphDefOptions($$self);
  }
} # end ::_ImportGraphDefOptions

package ML::TensorFlow::Graph {
  sub new {
    my ($class) = @_;
    my $g = ML::TensorFlow::CAPI::TF_NewGraph();
    return bless(\$g => $class);
  }

  sub new_from_graph_def {
    my ($class, $buffer, $opt) = @_;

    my $graph = ML::TensorFlow::Graph->new;
    my $import_opt = ML::TensorFlow::_ImportGraphDefOptions->new($opt);
    my $status = ML::TensorFlow::Status->new();

    ML::TensorFlow::CAPI::TF_GraphImportGraphDef(
      $$graph,
      $$buffer,
      $$import_opt,
      $$status
    );

    if (not $status->is_ok) {
      die("Failed to create new TF graph from graphdef: " . $status->get_message);
    }

    return $graph;
  }

  sub DESTROY {
    my ($self) = @_;
    ML::TensorFlow::CAPI::TF_DeleteGraph($$self);
  }
}; # end Graph


package ML::TensorFlow::Session {
  sub new {
    my ($class, $graph, $sessopt) = @_;

    if (!Scalar::Util::blessed($graph) || !$graph->isa("ML::TensorFlow::Graph")) {
      Carp::croak("Need a Graph object");
    }

    if (!Scalar::Util::blessed($sessopt) || !$sessopt->isa("ML::TensorFlow::SessionOptions")) {
      Carp::croak("Need a SessionOptions object");
    }

    my $status = ML::TensorFlow::Status->new;
    my $s = ML::TensorFlow::CAPI::TF_NewSession($$graph, $$sessopt, $$status);
    if (not $status->is_ok) {
      die("Failed to create new TF session: " . $status->get_message);
    }

    my $self = bless(\$s => $class);
    return $self;
  }

  sub DESTROY {
    my ($self) = @_;
    my $status = ML::TensorFlow::Status->new; # Mocking up status FIXME, what if that's not TF_OK?
    ML::TensorFlow::CAPI::TF_DeleteSession($$self, $$status);
    return;
  }

  sub close {
    my ($self) = @_;
    my $status = ML::TensorFlow::Status->new;
    ML::TensorFlow::CAPI::TF_CloseSession($$self, $$status);
    return $status;
  }

}; # end Session



package ML::TensorFlow::Tensor {

  my $dealloc_closure = sub {}; # memory managed by Perl (?)
  my $ffi_closure = $ML::TensorFlow::CAPI::FFI->closure($dealloc_closure);
  #my $opaque_closure = $ML::TensorFlow::CAPI::FFI->cast(tensor_dealloc_closure_t => 'opaque', $ffi_closure);

  sub new {
    my ($class, $type, $dims, $datablob) = @_;

    my $s = ML::TensorFlow::CAPI::TF_NewTensor(
      $type,
      $dims, scalar(@$dims),
      $datablob, bytes::length($datablob),
      $ffi_closure, 0 # as in: NULL
    );

    my $self = bless(\$s => $class);
    return $self;
  }

  sub DESTROY {
    my ($self) = @_;
    ML::TensorFlow::CAPI::TF_DeleteTensor($$self);
  }

  sub get_type {
    my ($self) = @_;
    return ML::TensorFlow::CAPI::TF_TensorType($$self);
  }

  sub get_num_dims {
    my ($self) = @_;
    return ML::TensorFlow::CAPI::TF_NumDims($$self);
  }

  sub get_dim_size {
    my ($self, $dim_index) = @_;
    return ML::TensorFlow::CAPI::TF_Dim($$self, $dim_index);
  }

  sub get_tensor_byte_size {
    my ($self) = @_;
    return ML::TensorFlow::CAPI::TF_TensorByteSize($$self);
  }

  sub get_tensordata {
    my ($self) = @_;
    my $bytes = ML::TensorFlow::CAPI::TF_TensorByteSize($$self);
    return ML::TensorFlow::CAPI::_make_perl_string_copy_from_opaque_string(
      ML::TensorFlow::CAPI::TF_TensorData($$self),
      $bytes
    );
  }
}; # end Tensor


1;

__END__

=head1 NAME

ML::TensorFlow - ...

=head1 SYNOPSIS

  use ML::TensorFlow;

=head1 DESCRIPTION

=head2 EXPORT

=head1 FUNCTIONS

=head1 SEE ALSO

=head1 AUTHOR

Steffen Mueller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.0 or,
at your option, any later version of Perl 5 you may have available.

=cut

