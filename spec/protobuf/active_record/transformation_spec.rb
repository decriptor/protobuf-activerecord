require 'spec_helper'

describe Protobuf::ActiveRecord::Transformation do
  let(:user) { User.new(user_attributes) }
  let(:user_attributes) { { :first_name => 'foo', :last_name => 'bar', :email => 'foo@test.co' } }
  let(:proto_hash) { { :name => 'foo bar', :email => 'foo@test.co' } }
  let(:proto) { UserMessage.new(proto_hash) }

  describe "._filter_attribute_fields" do
    it "includes fields that have values" do
      attribute_fields = User._filter_attribute_fields(proto)
      attribute_fields[:email].must_equal proto_hash[:email]
    end

    it "filters repeated fields" do
      attribute_fields = User._filter_attribute_fields(proto)
      attribute_fields.has_key?(:tags).must_equal false
    end

    it "includes attributes that aren't fields, but have attribute transformers" do
      User.stubs(:_protobuf_attribute_transformers).returns({ :account_id => :fetch_account_id })
      attribute_fields = User._filter_attribute_fields(proto)
      attribute_fields.has_key?(:account_id).must_equal true
    end

    it "includes fields that aren't attributes, but have attribute transformers" do
      attribute_fields = User._filter_attribute_fields(proto)
      attribute_fields.has_key?(:password).must_equal true
    end
  end

  describe "._protobuf_convert_fields_to_attributes" do
    context "when the given field's corresponding column type is :date" do
      let(:date) { Date.current }
      let(:value) { date.to_time.to_i }

      before { User.stubs(:_protobuf_date_column?).returns(true) }

      it "converts the given value to a Date object" do
        User._protobuf_convert_fields_to_attributes(:foo_date, value).must_equal date
      end
    end

    context "when given field's corresponding the column type is :datetime" do
      let(:datetime) { DateTime.current }
      let(:value) { datetime.to_i }

      before { User.stubs(:_protobuf_datetime_column?).returns(true) }

      it "converts the given value to a DateTime object" do
        User._protobuf_convert_fields_to_attributes(:foo_datetime, value).must_be_instance_of(DateTime)
      end

      it "converts the given value to a DateTime object of the same value" do
        User._protobuf_convert_fields_to_attributes(:foo_datetime, value).should be_within(1).of(datetime)
      end
    end

    context "when given field's corresponding the column type is :time" do
      let(:time) { Time.current }
      let(:value) { time.to_i }

      before { User.stubs(:_protobuf_time_column?).returns(true) }

      it "converts the given value to a Time object" do
        User._protobuf_convert_fields_to_attributes(:foo_time, value).must_be_instance_of(Time)
      end

      it "converts the given value to a Time object of the same value" do
        User._protobuf_convert_fields_to_attributes(:foo_time, value).should be_within(1).of(time)
      end
    end

    context "when given field's corresponding the column type is :timestamp" do
      let(:time) { Time.current }
      let(:value) { time.to_i }

      before { User.stubs(:_protobuf_timestamp_column?).returns(true) }

      it "converts the given value to a Time object" do
        User._protobuf_convert_fields_to_attributes(:foo_time, value).must_be_instance_of(Time)
      end

      it "converts the given value to a Time object of the same value" do
        User._protobuf_convert_fields_to_attributes(:foo_timestamp, value).should be_within(1).of(time)
      end
    end

    context "when no conversion is necessary" do
      let(:value) { "Foo" }

      it "returns the given value" do
        User._protobuf_convert_fields_to_attributes(:foo, value).must_equal value
      end
    end
  end

  describe ".attributes_from_proto" do
    context "when a transformer is defined for the attribute" do
      it "transforms the field value" do
        attribute_fields = User.attributes_from_proto(proto)
        attribute_fields[:first_name].must_equal user_attributes[:first_name]
      end
    end

    context "when a transformer is a callable that returns nil" do
      before do
        transformers = User._protobuf_attribute_transformers
        User.stubs(:_protobuf_attribute_transformers).returns(
          {:account_id => lambda { |proto| nil }}.merge(transformers)
        )
      end

      it "does not set the attribute" do
        attribute_fields = User.attributes_from_proto(proto)
        attribute_fields.must_equal user_attributes
      end
    end

    context "when a transformer is a callable that returns a value" do
      before do
        transformers = User._protobuf_attribute_transformers
        User.stubs(:_protobuf_attribute_transformers).returns(
          {:account_id => lambda { |proto| 1 }}.merge(transformers)
        )
      end

      it "sets the attribute" do
        attribute_fields = User.attributes_from_proto(proto)
        attribute_fields.must_equal user_attributes.merge(:account_id => 1)
      end
    end

    context "when a transformer is not defined for the attribute" do
      before {
        User.stubs(:_protobuf_convert_fields_to_attributes) do |key, value|
          value
        end
      }

      it "converts the field value" do
        attribute_fields = User.attributes_from_proto(proto)
        attribute_fields.must_equal user_attributes
      end
    end
  end

  describe ".attribute_from_proto" do
    context "when the given transformer is a symbol" do
      let(:callable) { lambda { |value| User.__send__(:extract_first_name) } }

      before { User.attribute_from_proto :first_name, :extract_first_name }

      it "creates a callable method object from the converter" do
        User.expects(:extract_first_name)
        User._protobuf_attribute_transformers[:first_name].call(1)
      end
    end

    context "when the given transformer is not callable" do
      it "raises an exception" do
        proc { User.attribute_from_proto :name, nil }.must_raise(Protobuf::ActiveRecord::AttributeTransformerError)
      end
    end

    context "when the given transformer is callable" do
      let(:callable) { lambda { |proto| nil } }

      before {
        User.stubs(:_protobuf_attribute_transformers).returns(Hash.new)
        User.attribute_from_proto :account_id, callable
      }

      it "adds the given converter to the list of protobuf field transformers" do
        User._protobuf_attribute_transformers[:account_id] = callable
      end
    end
  end

  describe ".convert_int64_to_date" do
    let(:date) { Date.current }
    let(:int64) { date.to_time.to_i }

    it "initializes a new Date object from the value" do
      Timecop.freeze(Date.current) do
        User.convert_int64_to_date(int64).must_equal date
      end
    end
  end

  describe ".convert_int64_to_datetime" do
    let(:datetime) { DateTime.current }
    let(:int64) { datetime.to_i }

    it "initializes a new DateTime object from the value" do
      Timecop.freeze(DateTime.current) do
        expected_datetime = Time.at(datetime.to_i)
        converted_datetime = User.convert_int64_to_datetime(int64)
        converted_datetime.must_equal expected_datetime
      end
    end
  end

  describe ".convert_int64_to_time" do
    let(:time) { Time.current }
    let(:int64) { time.to_time.to_i }

    it "initializes a new Time object from the value" do
      Timecop.freeze(Time.current) do
        User.convert_int64_to_time(int64).should be_within(1).of(time)
      end
    end
  end

  describe "#attributes_from_proto" do
    it "gets attributes from the given protobuf message" do
      User.expects(:attributes_from_proto).with(proto)
      user.attributes_from_proto(proto)
    end
  end
end
